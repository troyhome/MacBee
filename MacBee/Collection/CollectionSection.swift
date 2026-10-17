/// The tabs at the top of the Collection page.
enum CollectionSection: String, CaseIterable, Identifiable {
    case playlists, albums, tracks, videos, savedMixes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .tracks: "Tracks"
        case .videos: "Videos"
        case .savedMixes: "Saved Mixes"
        }
    }
}
