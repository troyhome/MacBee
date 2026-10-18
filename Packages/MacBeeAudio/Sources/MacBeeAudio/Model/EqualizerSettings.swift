import Foundation

/// A 16-band graphic equalizer with a preamp.
///
/// The EQ changes the audio, so it is never bit-perfect while it does anything. When it is off, or every
/// slider (preamp included) is at 0 dB, the engine takes it out of the signal path completely.
public struct EqualizerSettings: Codable, Sendable, Equatable {
    /// Centre frequencies of the 16 bands, in Hz.
    public static let frequencies: [Float] = [25, 40, 63, 100, 160, 250, 400, 630,
                                              1_000, 1_600, 2_500, 4_000, 6_300, 10_000, 16_000, 20_000]
    public static var bandCount: Int { frequencies.count }
    /// Slider range for bands and the preamp, in dB.
    public static let gainRange: ClosedRange<Float> = -12...12

    public var isEnabled: Bool
    /// Overall gain before the bands, in dB. Lower it when boosting bands to avoid clipping.
    public var preamp: Float
    /// One gain per band, in dB.
    public var gains: [Float]

    public init(isEnabled: Bool = false, preamp: Float = 0, gains: [Float] = Array(repeating: 0, count: 16)) {
        self.isEnabled = isEnabled
        self.preamp = Self.clamp(preamp)
        self.gains = Self.normalized(gains)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        preamp = Self.clamp(try c.decodeIfPresent(Float.self, forKey: .preamp) ?? 0)
        gains = Self.normalized(try c.decodeIfPresent([Float].self, forKey: .gains) ?? [])
    }

    public static let off = EqualizerSettings()

    /// True when every slider is at 0 dB.
    public var isFlat: Bool { preamp == 0 && gains.allSatisfy { $0 == 0 } }

    /// True when the EQ is in the signal path and changing the sound.
    public var isActive: Bool { isEnabled && !isFlat }

    /// Applies a preset's sliders, keeping the on/off switch.
    public mutating func apply(_ preset: EqualizerPreset) {
        preamp = Self.clamp(preset.preamp)
        gains = Self.normalized(preset.gains)
    }

    /// True when the sliders match `preset`.
    public func matches(_ preset: EqualizerPreset) -> Bool {
        preamp == Self.clamp(preset.preamp) && gains == Self.normalized(preset.gains)
    }

    static func clamp(_ value: Float) -> Float {
        min(max(value, gainRange.lowerBound), gainRange.upperBound)
    }

    /// Exactly 16 gains, each within range (missing ones are 0 dB).
    static func normalized(_ gains: [Float]) -> [Float] {
        (0..<bandCount).map { $0 < gains.count ? clamp(gains[$0]) : 0 }
    }
}

/// A named set of slider positions. Built-in presets ship with MacBee; custom ones are saved by the user.
public struct EqualizerPreset: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var preamp: Float
    public var gains: [Float]
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, preamp: Float, gains: [Float], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.preamp = EqualizerSettings.clamp(preamp)
        self.gains = EqualizerSettings.normalized(gains)
        self.isBuiltIn = isBuiltIn
    }

    /// Fixed ids so a chosen built-in preset is remembered across launches.
    private static func builtIn(_ n: UInt8, _ name: String, preamp: Float, _ gains: [Float]) -> EqualizerPreset {
        EqualizerPreset(id: UUID(uuid: (0x4D, 0x42, 0x45, 0x51, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, n)),
                        name: name, preamp: preamp, gains: gains, isBuiltIn: true)
    }

    //                                      25   40   63  100  160  250  400  630   1k 1.6k 2.5k   4k 6.3k  10k  16k  20k
    /// All sliders at 0 dB. Used by Reset; not in the preset menu (it sounds the same as no EQ).
    public static let flat = builtIn(1, "Flat", preamp: 0,
                                         [   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0])
    public static let typical = builtIn(2, "Typical", preamp: -3,
                                         [   3,   3, 2.5,   2,   1, 0.5,   0,   0,   0,   0, 0.5,   1, 1.5,   2,   2, 1.5])
    public static let punchy = builtIn(3, "Punchy", preamp: -4,
                                         [   4,   4, 3.5,   3,   2,   0,  -1,-1.5,  -1,   0,   1, 2.5, 3.5,   4,   4, 3.5])
    public static let reduceTreble = builtIn(4, "Reduce Treble", preamp: 0,
                                         [   1,   1,   1, 0.5,   0,   0,   0,   0,  -1,-1.5,  -2,-2.5,  -3,-3.5,  -4,  -4])
    public static let brite = builtIn(5, "Brite", preamp: -5,
                                         [ 5.5,   5, 4.5,   3,   1,   0,  -1,  -1,   0,   1, 1.5,   2,   3,   4, 4.5,   4])
    public static let indie = builtIn(6, "Indie", preamp: -3,
                                         [   2, 2.5, 2.5,   2,   1,   0,  -1,  -1,   0,   1,   2,   3,   3, 2.5,   2, 1.5])

    /// In the order shown in the preset menu.
    public static let builtIns: [EqualizerPreset] = [typical, punchy, reduceTreble, brite, indie]
}
