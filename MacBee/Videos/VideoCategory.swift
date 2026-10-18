/// The sections in the Videos sidebar, like the Apple TV app's library.
enum VideoCategory: String, CaseIterable, Identifiable {
    case recentlyAdded, movies, shows, fourK, musicVideos, genres, liked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .movies: "Movies"
        case .shows: "TV Shows"
        case .fourK: "4K HDR"
        case .musicVideos: "Music Videos"
        case .genres: "Genres"
        case .liked: "Liked"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyAdded: "clock"
        case .movies: "film"
        case .shows: "tv"
        case .fourK: "4k.tv"
        case .musicVideos: "music.note.tv"
        case .genres: "theatermasks"
        case .liked: "heart"
        }
    }
}
