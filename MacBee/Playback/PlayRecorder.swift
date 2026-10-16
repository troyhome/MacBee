import Foundation

/// Decides when a listen counts as a play (the rule is chosen in Preferences > General).
/// Each play is counted at most once.
struct PlayRecorder {
    private struct Key: Equatable {
        var url: URL
        var playId: Int
        var advance: Int
    }

    private var lastKey: Key?
    private var recorded = false

    /// `playId` changes each time the user starts a track and `advance` each time the queue moves on by itself,
    /// so replaying or repeating the same file counts again.
    mutating func shouldRecord(url: URL, playId: Int, advance: Int,
                               elapsed: TimeInterval, threshold: TimeInterval) -> Bool {
        let key = Key(url: url, playId: playId, advance: advance)
        if key != lastKey {
            lastKey = key
            recorded = false
        }
        guard !recorded, elapsed >= threshold else { return false }
        recorded = true
        return true
    }
}
