import Foundation

/// What a video folder holds. Music folders can also hold music videos.
public enum VideoFolderKind: String, Codable, Sendable {
    case moviesAndShows
    case musicVideos
}

/// One video file on disk.
public struct VideoFile: Codable, Hashable, Sendable {
    public var path: String
    public var size: Int64
    /// When the file appeared (creation date, or modification date if that's missing).
    public var added: Date
    /// 2160p / 4K / UHD in the name.
    public var is4K: Bool
    /// HDR, Dolby Vision or HDR10 in the name.
    public var isHDR: Bool

    public var url: URL { URL(fileURLWithPath: path) }

    public init(path: String, size: Int64, added: Date, is4K: Bool, isHDR: Bool) {
        self.path = path
        self.size = size
        self.added = added
        self.is4K = is4K
        self.isHDR = isHDR
    }
}

public struct Movie: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var year: Int?
    /// Best copy first (4K before HD, then the largest).
    public var files: [VideoFile]
    public var posterPath: String?
    public var genres: [String]
    /// A short description (from Plex).
    public var summary: String?

    public var id: String { files.first?.path ?? title }
    public var file: VideoFile? { files.first }
    public var added: Date { files.map(\.added).max() ?? .distantPast }
    public var is4K: Bool { files.contains(where: \.is4K) }
    public var isHDR: Bool { files.contains(where: \.isHDR) }
}

public struct Episode: Codable, Hashable, Sendable, Identifiable {
    public var season: Int
    public var number: Int
    /// The episode's own title when the file name has one, e.g. "My Return".
    public var title: String?
    public var file: VideoFile
    /// Other copies of the same episode (another video folder or drive). Only `file` is shown.
    public var otherFiles: [VideoFile]? = nil

    public var id: String { file.path }
    public var allFiles: [VideoFile] { [file] + (otherFiles ?? []) }
    /// e.g. "S1 · E3"
    public var code: String { "S\(season) · E\(number)" }
}

public struct Season: Codable, Hashable, Sendable, Identifiable {
    public var number: Int
    public var episodes: [Episode]
    public var id: Int { number }
}

public struct Show: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var year: Int?
    /// The show's folder.
    public var folderPath: String
    public var posterPath: String?
    public var genres: [String]
    public var seasons: [Season]
    /// A short description (from Plex).
    public var summary: String?

    public var id: String { folderPath }
    public var episodeCount: Int { seasons.reduce(0) { $0 + $1.episodes.count } }
    public var added: Date { seasons.flatMap(\.episodes).map(\.file.added).max() ?? .distantPast }
    public var is4K: Bool { seasons.contains { $0.episodes.contains(where: \.file.is4K) } }
    public var isHDR: Bool { seasons.contains { $0.episodes.contains(where: \.file.isHDR) } }
    /// The first episode, for Play.
    public var firstEpisode: Episode? { seasons.first?.episodes.first }
}

/// A music video found in a music folder.
public struct MusicVideo: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var folderName: String
    public var file: VideoFile
    /// Other copies of the same video (same name, another folder, drive or format). Only `file` is shown.
    public var otherFiles: [VideoFile]? = nil
    public var id: String { file.path }

    public var allFiles: [VideoFile] { [file] + (otherFiles ?? []) }
}

/// Everything found in the video folders.
public struct VideoCatalog: Codable, Sendable, Equatable {
    public var movies: [Movie] = []
    public var shows: [Show] = []
    public var musicVideos: [MusicVideo] = []
    public var scannedAt: Date?

    public init() {}

    public var isEmpty: Bool { movies.isEmpty && shows.isEmpty && musicVideos.isEmpty }
    public var genres: [String] {
        Set(movies.flatMap(\.genres) + shows.flatMap(\.genres)).sorted()
    }
}
