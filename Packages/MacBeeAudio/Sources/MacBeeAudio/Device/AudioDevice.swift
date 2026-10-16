import CoreAudio
import Foundation

/// A snapshot of one output device (DAC, built-in speakers, AirPlay, ...).
public struct AudioDevice: Identifiable, Hashable, Sendable {
    public let id: AudioObjectID
    /// Stable across reboots; this is what preferences store.
    public let uid: String
    public let name: String
    public let manufacturer: String
    /// Discrete sample rates the device accepts, ascending.
    public let supportedSampleRates: [Double]
    public let hasHardwareVolume: Bool
    /// Software device such as Boom 3D, Loopback or BlackHole. MacBee never changes its sample rate
    /// or bit depth: these devices often expect a fixed format and turn changes into loud noise.
    public let isVirtual: Bool

    public init(id: AudioObjectID, uid: String, name: String, manufacturer: String,
                supportedSampleRates: [Double], hasHardwareVolume: Bool, isVirtual: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.manufacturer = manufacturer
        self.supportedSampleRates = supportedSampleRates
        self.hasHardwareVolume = hasHardwareVolume
        self.isVirtual = isVirtual
    }

    public var maxSampleRate: Double { supportedSampleRates.last ?? 0 }
}

/// Picks the device sample rate for a track. Pure logic, unit-tested.
public enum SampleRatePolicy {
    /// Common rates used to expand continuous ranges reported by some devices.
    public static let standardRates: [Double] = [
        44_100, 48_000, 88_200, 96_000, 176_400, 192_000, 352_800, 384_000, 705_600, 768_000,
    ]

    /// Exact match if possible. Otherwise prefer the same rate family (44.1k or 48k),
    /// taking the highest rate at or below the source, then the lowest above it.
    public static func bestRate(for source: Double, supported: [Double]) -> Double? {
        let rates = supported.sorted()
        guard !rates.isEmpty else { return nil }
        if let exact = rates.first(where: { abs($0 - source) < 0.5 }) { return exact }

        let family: Double = source.truncatingRemainder(dividingBy: 44_100) == 0 ? 44_100 : 48_000
        let sameFamily = rates.filter { $0.truncatingRemainder(dividingBy: family) == 0 }
        if let below = sameFamily.last(where: { $0 < source }) { return below }
        if let above = sameFamily.first(where: { $0 > source }) { return above }

        if let below = rates.last(where: { $0 < source }) { return below }
        return rates.first
    }

    /// Turns HAL ranges into a list of discrete rates.
    public static func expand(ranges: [(min: Double, max: Double)]) -> [Double] {
        var result = Set<Double>()
        for r in ranges {
            if abs(r.max - r.min) < 0.5 {
                result.insert(r.min)
            } else {
                standardRates.filter { $0 >= r.min && $0 <= r.max }.forEach { result.insert($0) }
            }
        }
        return result.sorted()
    }
}
