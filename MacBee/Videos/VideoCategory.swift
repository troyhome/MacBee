/// The sections in the Videos sidebar, like the Apple TV app's library. `liked` is Collections > Videos.
enum VideoCategory: String, CaseIterable, Identifiable {
    case recentlyPlayed, movies, shows, musicVideos, genres, liked

    /// What the Videos sidebar lists.
    static let sidebar: [VideoCategory] = [.recentlyPlayed, .movies, .shows, .musicVideos, .genres]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyPlayed: "Recently Played"
        case .movies: "Movies"
        case .shows: "TV Shows"
        case .musicVideos: "Music Videos"
        case .genres: "Genres"
        case .liked: "Liked"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .movies: "film"
        case .shows: "tv"
        case .musicVideos: "music.note.tv"
        case .genres: "theatermasks"
        case .liked: "heart"
        }
    }
}
