/// The tabs at the top of the Collections page. Albums, Tracks and Videos are the liked (hearted) ones and
/// sit together in their own group.
enum CollectionSection: String, CaseIterable, Identifiable {
    case playlists, variousArtists, savedMixes, albums, tracks, videos

    var id: String { rawValue }

    /// The tabs before the liked group, and the liked group.
    static let general: [CollectionSection] = [.playlists, .variousArtists, .savedMixes]
    static let liked: [CollectionSection] = [.albums, .tracks, .videos]

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .variousArtists: "Various Artists"
        case .savedMixes: "Saved Mixes"
        case .albums: "Albums"
        case .tracks: "Tracks"
        case .videos: "Videos"
        }
    }
}
