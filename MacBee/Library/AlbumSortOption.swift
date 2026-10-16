import MacBeeLibrary

/// Sort choices for the album grid (saved between launches).
enum AlbumSortOption: String, CaseIterable, Identifiable {
    case artist, title, year, recentlyAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artist: "Artist"
        case .title: "Title"
        case .year: "Year"
        case .recentlyAdded: "Recently Added"
        }
    }

    var librarySort: AlbumSort {
        switch self {
        case .artist: .artist
        case .title: .title
        case .year: .year
        case .recentlyAdded: .recentlyAdded
        }
    }
}
