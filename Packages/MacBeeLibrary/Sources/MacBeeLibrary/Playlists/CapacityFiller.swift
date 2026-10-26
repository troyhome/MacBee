import Foundation

/// MiniDisc mixes (roadmap Phase 3): fills a playlist up to a running time (60:00, 74:00 or 80:00) and says whether
/// it's over time or has too much room left. Pure logic, unit-tested.
public enum CapacityFiller {
    public enum Status: Equatable, Sendable {
        case fits
        /// Longer than the disc; by how many seconds.
        case overtime(Double)
        /// More than 7 minutes unused; how many seconds are free.
        case underfill(Double)
    }

    /// The disc sizes offered: 60, 74 and 80 minutes.
    public static let templates: [(title: String, seconds: Int)] = [("60min MD Mix", 60 * 60), ("74min MD Mix", 74 * 60),
                                                                     ("80min MD Mix", 80 * 60)]
    /// More free time than this is flagged as underfilled.
    public static let underfillLimit: Double = 7 * 60

    public static func status(total: Double, capacity: Double) -> Status {
        if total > capacity { return .overtime(total - capacity) }
        if capacity - total > underfillLimit { return .underfill(capacity - total) }
        return .fits
    }

    /// Picks songs from `candidates` (in the order given, usually shuffled) that fit in the time left after
    /// `existing`. It goes through every candidate, so shorter songs fill gaps a long one couldn't.
    public static func fill(existing: [Track], candidates: [Track], capacity: Double) -> [Track] {
        var used = existing.reduce(0) { $0 + $1.duration }
        var taken = Set(existing.map(\.path))
        var picked: [Track] = []
        for track in candidates where track.duration > 0 && !taken.contains(track.path) {
            if used + track.duration <= capacity {
                picked.append(track)
                used += track.duration
                taken.insert(track.path)
            }
            if capacity - used < 60 { break } // under a minute left: nothing will fit
        }
        return picked
    }
}
