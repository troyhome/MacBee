/// The tabs at the top of the Collections page. Albums, Tracks and Videos are the liked (hearted) ones and
/// sit together in their own group.
enum CollectionSection: String, CaseIterable, Identifiable {
    case playlists, variousArtists, savedMixes, albums, tracks, videos

    var id: String { rawValue }

    /// The tabs before the liked group, and the liked group.
    /// Playlists have their own page (sidebar > Playlists); the case stays so an old saved choice still reads.
    static let general: [CollectionSection] = [.variousArtists, .savedMixes]
    static let liked: [CollectionSection] = [.albums, .tracks, .videos]

    var systemImage: String {
        switch self {
        case .playlists: "music.note.list"
        case .variousArtists: "person.3"
        case .savedMixes: "square.stack.3d.up"
        case .albums: "square.stack"
        case .tracks: "music.note"
        case .videos: "play.rectangle"
        }
    }

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
