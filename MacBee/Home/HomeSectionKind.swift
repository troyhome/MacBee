/// The blocks on the Music (Home) page. Their order (and which show) is set in Settings > General.
enum HomeSectionKind: String, CaseIterable, Identifiable {
    case stats, recentlyPlayed, suggestedMixes, recentlyAdded, forgottenGems, playHistory, library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stats: "Library Stats"
        case .recentlyPlayed: "Recently Played"
        case .suggestedMixes: "Suggested Mixes"
        case .recentlyAdded: "Recently Added"
        case .forgottenGems: "Forgotten Gems"
        case .playHistory: "Play History"
        case .library: "Library (scan and folders)"
        }
    }

    var systemImage: String {
        switch self {
        case .stats: "number.square"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .suggestedMixes: "square.stack.3d.up"
        case .recentlyAdded: "clock.badge.plus"
        case .forgottenGems: "sparkles"
        case .playHistory: "list.bullet.rectangle"
        case .library: "externaldrive"
        }
    }
}
