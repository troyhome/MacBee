/// Destinations in the sidebar.
enum SidebarItem: String, CaseIterable, Identifiable {
    case search, playingFrom, home, collection, videos, artists, albums, playlists, tags, playlistStudio

    var id: String { rawValue }

    static let library: [SidebarItem] = [.home, .collection, .videos, .artists, .albums, .playlists, .tags]

    var title: String {
        switch self {
        case .search: "Search"
        case .playingFrom: "Playing From"
        case .home: "Music"
        case .collection: "Collections"
        case .videos: "Videos"
        case .artists: "Artists"
        case .albums: "Albums"
        case .playlists: "Playlists"
        case .tags: "Tags"
        case .playlistStudio: "Playlist Studio"
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .playingFrom: "waveform"
        case .home: "house"
        case .collection: "heart.square"
        case .videos: "play.rectangle"
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .playlists: "music.note.list"
        case .tags: "tag"
        case .playlistStudio: "wand.and.stars"
        }
    }
}
