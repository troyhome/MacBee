import Foundation

/// Codec families MacBee cares about for display and signal-path decisions.
public enum AudioCodec: String, Sendable, Equatable {
    case flac = "FLAC"
    case alac = "ALAC"
    case wav = "WAV"
    case aiff = "AIFF"
    case mp3 = "MP3"
    case aac = "AAC"
    case dsd = "DSD"
    case other = "PCM"
}

/// A plain description of a track's audio format, independent of the decoding library.
public struct AudioFormatInfo: Sendable, Equatable {
    /// Codec of the file on disk.
    public var codec: AudioCodec
    /// Sample rate of the file on disk (for DSD, the 1-bit rate, e.g. 2,822,400 Hz).
    public var sourceSampleRate: Double
    /// Bit depth of the file on disk. `nil` for lossy or unknown, `1` for DSD.
    public var bitDepth: Int?
    public var channels: Int
    public var isLossless: Bool
    /// Sample rate the decoder hands to CoreAudio (for DoP DSD64 this is 176,400 Hz).
    public var deliveredSampleRate: Double

    public init(codec: AudioCodec, sourceSampleRate: Double, bitDepth: Int?, channels: Int,
                isLossless: Bool, deliveredSampleRate: Double? = nil) {
        self.codec = codec
        self.sourceSampleRate = sourceSampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.isLossless = isLossless
        self.deliveredSampleRate = deliveredSampleRate ?? sourceSampleRate
    }

    public var isDSD: Bool { codec == .dsd }

    /// e.g. "DSD64", "DSD128". `nil` when not DSD.
    public var dsdRateName: String? {
        guard isDSD, sourceSampleRate > 0 else { return nil }
        let base: Double = sourceSampleRate.truncatingRemainder(dividingBy: 44_100) == 0 ? 44_100 : 48_000
        return "DSD\(Int((sourceSampleRate / base).rounded()))"
    }

    /// Short label for the UI, e.g. "FLAC 24-bit / 96 kHz", "MP3 44.1 kHz", "DSD64".
    public var displayString: String {
        if let dsd = dsdRateName { return dsd }
        let rate = Self.formatRate(sourceSampleRate)
        if let bits = bitDepth { return "\(codec.rawValue) \(bits)-bit / \(rate)" }
        return "\(codec.rawValue) \(rate)"
    }

    /// 44100 -> "44.1 kHz", 96000 -> "96 kHz"
    public static func formatRate(_ hz: Double) -> String {
        let khz = hz / 1000
        if khz.rounded() == khz { return "\(Int(khz)) kHz" }
        return String(format: "%.1f kHz", khz)
    }

    /// ALAC stores the original bit depth in its format flags (1 = 16, 2 = 20, 3 = 24, 4 = 32).
    public static func bitDepth(fromALACFlags flags: UInt32) -> Int? {
        switch flags {
        case 1: return 16
        case 2: return 20
        case 3: return 24
        case 4: return 32
        default: return nil
        }
    }
}
