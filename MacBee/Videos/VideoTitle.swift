import Foundation
import MacBeeVideo

/// A movie, show or music video, so pages can list them together.
enum VideoTitle: Identifiable, Hashable {
    case movie(Movie)
    case show(Show)
    case musicVideo(MusicVideo)

    var id: String {
        switch self {
        case let .movie(movie): movie.id
        case let .show(show): show.id
        case let .musicVideo(video): video.id
        }
    }

    var title: String {
        switch self {
        case let .movie(movie): movie.title
        case let .show(show): show.title
        case let .musicVideo(video): video.title
        }
    }

    /// Year, or the number of seasons for shows.
    var subtitle: String {
        switch self {
        case let .movie(movie): return movie.year.map(String.init) ?? ""
        case let .show(show):
            let seasons = show.seasons.count == 1 ? "1 season" : "\(show.seasons.count) seasons"
            return [show.year.map(String.init), seasons].compactMap { $0 }.joined(separator: " · ")
        case let .musicVideo(video): return video.folderName
        }
    }

    var posterPath: String? {
        switch self {
        case let .movie(movie): movie.posterPath
        case let .show(show): show.posterPath
        case .musicVideo: nil
        }
    }

    /// The file to take a still picture from when there's no poster.
    var previewFile: VideoFile? {
        switch self {
        case let .movie(movie): movie.file
        case let .show(show): show.firstEpisode?.file
        case let .musicVideo(video): video.file
        }
    }

    var added: Date {
        switch self {
        case let .movie(movie): movie.added
        case let .show(show): show.added
        case let .musicVideo(video): video.file.added
        }
    }

    var is4K: Bool {
        switch self {
        case let .movie(movie): movie.is4K
        case let .show(show): show.is4K
        case let .musicVideo(video): video.file.is4K
        }
    }

    var isHDR: Bool {
        switch self {
        case let .movie(movie): movie.isHDR
        case let .show(show): show.isHDR
        case let .musicVideo(video): video.file.isHDR
        }
    }

    var genres: [String] {
        switch self {
        case let .movie(movie): movie.genres
        case let .show(show): show.genres
        case .musicVideo: []
        }
    }
}
