import Foundation

/// For playing into a recorder (MiniDisc, cassette) instead of listening.
/// - `gap`: seconds of silence between songs, so the recorder starts a new track number for each one.
///   Songs are never joined gaplessly in this mode.
/// - `maxSampleRate`: the highest rate the output is switched to. MiniDisc records at 44.1 kHz and its
///   optical input only takes 32, 44.1 or 48 kHz, so hi-res songs are converted down (not bit-perfect).
public struct RecordOutMode: Sendable, Equatable {
    public var gap: TimeInterval
    public var maxSampleRate: Double?

    public init(gap: TimeInterval = 3, maxSampleRate: Double? = 48_000) {
        self.gap = gap
        self.maxSampleRate = maxSampleRate
    }

    /// The device rates allowed under `maxSampleRate`. Falls back to all of them if none qualify.
    public func allowedRates(_ supported: [Double]) -> [Double] {
        guard let cap = maxSampleRate else { return supported }
        let allowed = supported.filter { $0 <= cap + 0.5 }
        return allowed.isEmpty ? supported : allowed
    }
}
