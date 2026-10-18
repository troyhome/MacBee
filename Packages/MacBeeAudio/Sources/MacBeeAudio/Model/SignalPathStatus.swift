import Foundation

/// What is happening to the audio between the file and the DAC.
/// The UI uses this for the "Bit-Perfect" badge and its tooltip.
public struct SignalPathStatus: Sendable, Equatable {

    /// Things that change the audio data (break bit-perfect).
    public enum Issue: Sendable, Equatable {
        case resampled(from: Double, to: Double)
        case softwareVolume(Float)
        case bitDepthReduced(from: Int, to: Int)
        case dsdConvertedToPCM
        /// Playing through a software device (e.g. Boom 3D) that may add effects or convert the audio.
        case virtualDevice
        /// The equalizer is on and shaping the sound.
        case equalizer
    }

    /// Informational notes that don't change the data.
    public enum Note: Sendable, Equatable {
        /// Other apps can play through the same device at the same time.
        case sharedMode
        /// Source is lossy (MP3/AAC); output is bit-perfect to the decoded audio.
        case lossySource
    }

    public var issues: [Issue]
    public var notes: [Note]

    public var isBitPerfect: Bool { issues.isEmpty }

    public init(issues: [Issue] = [], notes: [Note] = []) {
        self.issues = issues
        self.notes = notes
    }

    /// Everything needed to judge the signal path. Plain values, so it's easy to test.
    public struct Input: Sendable, Equatable {
        public var format: AudioFormatInfo
        public var dsdMode: DSDPlaybackMode
        public var deviceSampleRate: Double
        public var deviceBitDepth: Int?
        public var volumeMode: VolumeMode
        public var softwareVolume: Float
        public var exclusiveMode: Bool
        public var isVirtualDevice: Bool
        public var equalizerActive: Bool

        public init(format: AudioFormatInfo, dsdMode: DSDPlaybackMode, deviceSampleRate: Double,
                    deviceBitDepth: Int?, volumeMode: VolumeMode, softwareVolume: Float, exclusiveMode: Bool,
                    isVirtualDevice: Bool = false, equalizerActive: Bool = false) {
            self.format = format
            self.dsdMode = dsdMode
            self.deviceSampleRate = deviceSampleRate
            self.deviceBitDepth = deviceBitDepth
            self.volumeMode = volumeMode
            self.softwareVolume = softwareVolume
            self.exclusiveMode = exclusiveMode
            self.isVirtualDevice = isVirtualDevice
            self.equalizerActive = equalizerActive
        }
    }

    public static func evaluate(_ input: Input) -> SignalPathStatus {
        var issues: [Issue] = []
        var notes: [Note] = []
        let format = input.format

        if input.isVirtualDevice {
            issues.append(.virtualDevice)
        }
        if input.equalizerActive {
            issues.append(.equalizer)
        }
        if format.isDSD && input.dsdMode == .pcmConversion {
            issues.append(.dsdConvertedToPCM)
        }
        if input.deviceSampleRate > 0, abs(input.deviceSampleRate - format.deliveredSampleRate) > 0.5 {
            issues.append(.resampled(from: format.deliveredSampleRate, to: input.deviceSampleRate))
        }
        if input.volumeMode == .software && input.softwareVolume < 0.9999 {
            issues.append(.softwareVolume(input.softwareVolume))
        }
        // DoP carries 24-bit words, so the device needs at least 24 bits.
        let neededBits: Int? = format.isDSD ? (input.dsdMode == .dop ? 24 : nil) : format.bitDepth
        if let needed = neededBits, let device = input.deviceBitDepth, device < needed {
            issues.append(.bitDepthReduced(from: needed, to: device))
        }

        if !input.exclusiveMode { notes.append(.sharedMode) }
        if !format.isLossless { notes.append(.lossySource) }

        return SignalPathStatus(issues: issues, notes: notes)
    }

    /// Plain-language lines for a tooltip.
    public var summaryLines: [String] {
        var lines: [String] = [isBitPerfect ? "Bit-perfect" : "Not bit-perfect"]
        for issue in issues {
            switch issue {
            case let .resampled(from, to):
                lines.append("Resampled \(AudioFormatInfo.formatRate(from)) → \(AudioFormatInfo.formatRate(to)) (device doesn't support the original rate)")
            case let .softwareVolume(v):
                lines.append("Software volume at \(Int((v * 100).rounded()))%")
            case let .bitDepthReduced(from, to):
                lines.append("Bit depth reduced \(from)-bit → \(to)-bit")
            case .dsdConvertedToPCM:
                lines.append("DSD converted to PCM (enable DoP if your DAC supports it)")
            case .equalizer:
                lines.append("Equalizer is on and changing the sound. Turn it off (or choose Flat) for bit-perfect playback.")
            case .virtualDevice:
                lines.append("Playing through a virtual device (like Boom 3D), which may change the sound. MacBee leaves its settings alone. Pick your speakers or DAC for bit-perfect playback.")
            }
        }
        for note in notes {
            switch note {
            case .sharedMode: lines.append("Shared mode: other apps may mix in. Turn on Exclusive Mode to prevent this.")
            case .lossySource: lines.append("Lossy source")
            }
        }
        return lines
    }
}
