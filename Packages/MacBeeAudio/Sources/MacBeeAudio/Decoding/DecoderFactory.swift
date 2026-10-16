import AVFoundation
import Foundation
import SFBAudioEngine

/// Creates the right SFBAudioEngine decoder for a file, including the DSD path.
public struct DecoderFactory: Sendable {
    public var dsdMode: DSDPlaybackMode
    /// Load each file fully into memory before playing, so slow or busy
    /// network drives can't cause dropouts. Files over `maxInMemoryBytes` are read normally.
    public var loadIntoMemory: Bool
    public var maxInMemoryBytes: Int

    public init(dsdMode: DSDPlaybackMode = .pcmConversion,
                loadIntoMemory: Bool = true,
                maxInMemoryBytes: Int = 1_500_000_000) {
        self.dsdMode = dsdMode
        self.loadIntoMemory = loadIntoMemory
        self.maxInMemoryBytes = maxInMemoryBytes
    }

    private static let dsdExtensions: Set<String> = ["dsf", "dff"]

    /// File extensions MacBee can play. The library scanner uses this in Phase 2.
    public static var supportedExtensions: Set<String> {
        AudioDecoder.supportedPathExtensions.union(dsdExtensions)
    }

    public static func isDSD(_ url: URL) -> Bool {
        dsdExtensions.contains(url.pathExtension.lowercased())
    }

    /// Loads the file in the background and returns an opened decoder.
    /// Use this from the main actor so the UI never waits on the network.
    public func loadDecoder(for url: URL) async throws -> PCMDecoding {
        let factory = self
        let box = try await Task.detached(priority: .userInitiated) {
            DecoderBox(decoder: try factory.makeDecoder(for: url))
        }.value
        return box.decoder
    }

    /// Returns an opened decoder, ready to read its format. Blocks while the file loads.
    public func makeDecoder(for url: URL) throws -> PCMDecoding {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            throw AudioEngineError.unsupportedFile(url)
        }
        do {
            let input = try InputSource(for: url, flags: shouldLoadIntoMemory(url) ? .loadFilesInMemory : [])
            let decoder: PCMDecoding
            if Self.isDSD(url) {
                switch dsdMode {
                case .dop: decoder = try DoPDecoder(inputSource: input)
                case .pcmConversion: decoder = try DSDPCMDecoder(inputSource: input)
                }
            } else {
                decoder = try AudioDecoder(inputSource: input)
            }
            try decoder.open()
            return decoder
        } catch let error as AudioEngineError {
            throw error
        } catch {
            throw AudioEngineError.decoderFailed(url, error.localizedDescription)
        }
    }

    private func shouldLoadIntoMemory(_ url: URL) -> Bool {
        guard loadIntoMemory else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0 && size <= maxInMemoryBytes
    }

    /// Reads a library-independent format description from an opened decoder.
    public static func formatInfo(for decoder: PCMDecoding, url: URL) -> AudioFormatInfo {
        let source = decoder.sourceFormat.streamDescription.pointee
        let delivered = decoder.processingFormat.sampleRate
        let codec = codec(for: source.mFormatID, url: url)

        var bits: Int?
        switch codec {
        case .dsd: bits = 1
        case .alac: bits = AudioFormatInfo.bitDepth(fromALACFlags: source.mFormatFlags)
        case .mp3, .aac: bits = nil
        default: bits = source.mBitsPerChannel > 0 ? Int(source.mBitsPerChannel) : nil
        }

        return AudioFormatInfo(codec: codec,
                               sourceSampleRate: source.mSampleRate,
                               bitDepth: bits,
                               channels: Int(source.mChannelsPerFrame),
                               isLossless: decoder.decodingIsLossless,
                               deliveredSampleRate: delivered)
    }

    private static let dsdFormatID: AudioFormatID = 0x4453_4420 // 'DSD '

    static func codec(for formatID: AudioFormatID, url: URL) -> AudioCodec {
        switch formatID {
        case kAudioFormatFLAC: return .flac
        case kAudioFormatAppleLossless: return .alac
        case kAudioFormatMPEGLayer3: return .mp3
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: return .aac
        case dsdFormatID: return .dsd
        default: break
        }
        switch url.pathExtension.lowercased() {
        case "flac": return .flac
        case "wav", "wave": return .wav
        case "aif", "aiff", "aifc": return .aiff
        case "mp3": return .mp3
        case "dsf", "dff": return .dsd
        default: return .other
        }
    }
}

/// Carries a decoder from the background loading task back to the engine.
/// Safe because the decoder isn't touched by the loading task after it's handed over.
private struct DecoderBox: @unchecked Sendable {
    let decoder: PCMDecoding
}
