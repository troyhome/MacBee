import Foundation

/// How volume is applied.
public enum VolumeMode: String, Codable, Sendable, CaseIterable {
    /// Adjust the DAC's own volume control. The digital stream stays untouched (bit-perfect).
    case hardware
    /// Scale samples in software. Convenient, but no longer bit-perfect below 100%.
    case software
}

/// How DSD (.dsf / .dff) files are sent to the DAC.
public enum DSDPlaybackMode: String, Codable, Sendable, CaseIterable {
    /// Convert DSD64 to PCM. Works on any DAC, not bit-perfect.
    case pcmConversion
    /// DSD over PCM. Bit-perfect, but the DAC must support DoP or you will hear noise.
    case dop
}

/// User-facing output preferences. Persisted later by the app's PreferencesStore.
public struct OutputSettings: Codable, Sendable, Equatable {
    /// Unique ID of the chosen output device, or `nil` to follow the macOS default.
    public var deviceUID: String?
    /// Take exclusive (hog) access to the device. Off by default so other apps aren't silenced unexpectedly.
    public var exclusiveMode: Bool
    public var volumeMode: VolumeMode
    /// Software gain, 0...1. Only used when `volumeMode == .software`.
    public var softwareVolume: Float
    public var dsdMode: DSDPlaybackMode
    /// Switch the device to the highest integer bit depth it offers at the track's sample rate.
    public var preferHighestBitDepth: Bool
    /// Load each track fully into memory before it plays (protects against network-drive dropouts).
    public var loadIntoMemory: Bool

    public init(deviceUID: String? = nil,
                exclusiveMode: Bool = false,
                volumeMode: VolumeMode = .hardware,
                softwareVolume: Float = 1.0,
                dsdMode: DSDPlaybackMode = .pcmConversion,
                preferHighestBitDepth: Bool = true,
                loadIntoMemory: Bool = true) {
        self.deviceUID = deviceUID
        self.exclusiveMode = exclusiveMode
        self.volumeMode = volumeMode
        self.softwareVolume = softwareVolume
        self.dsdMode = dsdMode
        self.preferHighestBitDepth = preferHighestBitDepth
        self.loadIntoMemory = loadIntoMemory
    }

    /// Settings saved by older versions lack newer keys; those get their defaults instead of failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OutputSettings.default
        deviceUID = try c.decodeIfPresent(String.self, forKey: .deviceUID)
        exclusiveMode = try c.decodeIfPresent(Bool.self, forKey: .exclusiveMode) ?? d.exclusiveMode
        volumeMode = try c.decodeIfPresent(VolumeMode.self, forKey: .volumeMode) ?? d.volumeMode
        softwareVolume = try c.decodeIfPresent(Float.self, forKey: .softwareVolume) ?? d.softwareVolume
        dsdMode = try c.decodeIfPresent(DSDPlaybackMode.self, forKey: .dsdMode) ?? d.dsdMode
        preferHighestBitDepth = try c.decodeIfPresent(Bool.self, forKey: .preferHighestBitDepth) ?? d.preferHighestBitDepth
        loadIntoMemory = try c.decodeIfPresent(Bool.self, forKey: .loadIntoMemory) ?? d.loadIntoMemory
    }

    public static let `default` = OutputSettings()
}
