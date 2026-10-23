import Foundation

/// Which page MacBee shows when it opens.
enum StartPage: String, CaseIterable, Identifiable {
    case home, artists, albums, lastPage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Media"
        case .artists: "Artists"
        case .albums: "Albums"
        case .lastPage: "Where I left off"
        }
    }
}

/// When a listen counts as a play (for play counts, Recently Played and history).
enum PlayCountRule: String, CaseIterable, Identifiable {
    case halfOrFourMinutes, thirtySeconds, nearlyFinished
    var id: String { rawValue }
    var title: String {
        switch self {
        case .halfOrFourMinutes: "After half the song, or 4 minutes for long songs"
        case .thirtySeconds: "After 30 seconds"
        case .nearlyFinished: "Only when nearly finished (90%)"
        }
    }

    func threshold(forDuration duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return 4 * 60 }
        switch self {
        case .halfOrFourMinutes: return min(duration * 0.5, 4 * 60)
        case .thirtySeconds: return min(30, duration * 0.9)
        case .nearlyFinished: return duration * 0.9
        }
    }
}

/// How often network folders are re-checked for changes made from other computers.
enum RoutineCheck: Int, CaseIterable, Identifiable {
    case off = 0, every15 = 15, every30 = 30, every60 = 60
    var id: Int { rawValue }
    var title: String { self == .off ? "Off" : "Every \(rawValue) minutes" }
    var interval: TimeInterval? { self == .off ? nil : TimeInterval(rawValue * 60) }
}
