import Foundation

// MARK: - Play history

/// One listen, from the `play` table.
public struct PlayHistoryEntry: Identifiable, Hashable, Sendable {
    public var playId: Int64
    public var playedAt: Date
    public var track: Track
    public var id: Int64 { playId }
}

/// Plays from one calendar day, for the Home screen's Play History.
public struct PlayHistoryDay: Identifiable, Hashable, Sendable {
    /// "Today", "Yesterday" or a date like "Monday, October 12".
    public var title: String
    public var day: Date
    public var entries: [PlayHistoryEntry]
    public var id: Date { day }
}

public enum PlayHistory {
    /// Groups plays (newest first) by calendar day, keeping their order.
    public static func groupByDay(_ entries: [PlayHistoryEntry], now: Date = Date(),
                                  calendar: Calendar = .current) -> [PlayHistoryDay] {
        var days: [PlayHistoryDay] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.playedAt)
            if days.last?.day == day {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(PlayHistoryDay(title: title(for: day, now: now, calendar: calendar), day: day, entries: [entry]))
            }
        }
        return days
    }

    static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: today)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEMMMMd" : "EEEEMMMMdyyyy")
        return formatter.string(from: day)
    }
}

// MARK: - Suggested mixes

/// An automatic playlist on the Home screen.
public struct Mix: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case mostPlayed
        case genre(String)
        /// First year of the decade, e.g. 1990.
        case decade(Int)
        case hiRes
        case favorites
    }

    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var tracks: [Track]

    public var id: Kind { kind }

    /// Up to four different covers for the card's collage.
    public var artworkIds: [Int64] {
        var seen: [Int64] = []
        for id in tracks.compactMap(\.artworkId) where !seen.contains(id) {
            seen.append(id)
            if seen.count == 4 { break }
        }
        return seen
    }
}
