import Foundation
import OSLog

private let plexVideoLog = Logger(subsystem: "com.troyhomenchuk.MacBee", category: "PlexVideos")

/// What Plex knows about a movie or show, looked up by the video's file name.
struct PlexVideoInfo: Codable, Sendable {
    var title: String
    var year: Int?
    var genres: [String]
    var summary: String?
    /// Plex's poster path, for `PlexConnection.posterFile`.
    var thumb: String?
    /// The poster downloaded to this Mac.
    var posterPath: String?
}

/// Plex movie and show details keyed by file name (just the name, since Plex sees the drive under a
/// different path than this Mac does).
struct PlexVideoIndex: Codable, Sendable {
    var movies: [String: PlexVideoInfo] = [:]
    var shows: [String: PlexVideoInfo] = [:]

    /// Kept on this Mac so titles, posters and summaries stay when Plex can't be reached (or isn't signed in).
    static var savedURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee/plex-videos.json")
    }

    static func loadSaved() -> PlexVideoIndex? {
        guard let data = try? Data(contentsOf: savedURL) else { return nil }
        return try? JSONDecoder().decode(PlexVideoIndex.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.savedURL, options: .atomic) }
    }

    static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent.lowercased()
    }
}

extension PlexConnection {
    /// Reads every Plex movie and TV library. Nil when not signed in or the server can't be reached.
    func videoIndex() async -> PlexVideoIndex? {
        guard isSignedIn else {
            plexVideoLog.notice("Plex videos: not signed in")
            return nil
        }
        guard let (base, token) = await serverAccess() else {
            plexVideoLog.notice("Plex videos: no server reachable")
            return nil
        }
        let api = PlexAPI()
        let sections: [PlexSection]
        do {
            sections = try await api.videoSections(base: base, token: token)
        } catch {
            plexVideoLog.notice("Plex videos: sections failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        plexVideoLog.notice("Plex videos: \(sections.count) movie/TV libraries")
        var index = PlexVideoIndex()
        for section in sections {
            if section.type == "movie" {
                let movies = (try? await api.allVideoItems(base: base, token: token, sectionKey: section.key, type: 1)) ?? []
                for movie in movies {
                    let info = PlexVideoInfo(title: movie.title ?? "", year: movie.year, genres: movie.genres?.map(\.tag) ?? [],
                                             summary: movie.summary, thumb: movie.thumb)
                    for file in movie.files { index.movies[PlexVideoIndex.fileName(file)] = info }
                }
            } else {
                let shows = (try? await api.allVideoItems(base: base, token: token, sectionKey: section.key, type: 2)) ?? []
                var showInfo: [String: PlexVideoInfo] = [:]
                for show in shows {
                    guard let key = show.ratingKey else { continue }
                    showInfo[key] = PlexVideoInfo(title: show.title ?? "", year: show.year, genres: show.genres?.map(\.tag) ?? [],
                                                  summary: show.summary, thumb: show.thumb)
                }
                let episodes = (try? await api.allVideoItems(base: base, token: token, sectionKey: section.key, type: 4)) ?? []
                for episode in episodes {
                    guard let key = episode.grandparentRatingKey else { continue }
                    let info = showInfo[key] ?? PlexVideoInfo(title: episode.grandparentTitle ?? "", year: nil, genres: [],
                                                             summary: nil, thumb: episode.grandparentThumb)
                    for file in episode.files { index.shows[PlexVideoIndex.fileName(file)] = info }
                }
            }
        }
        plexVideoLog.notice("Plex videos: \(index.movies.count) movie files, \(index.shows.count) episode files")
        return index
    }

    /// A poster saved on this Mac (downloaded once, then reused).
    func posterFile(for thumb: String) async -> String? {
        let name = thumb.replacingOccurrences(of: "/", with: "_") + ".jpg"
        let destination = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee/Posters/\(name)")
        if FileManager.default.fileExists(atPath: destination.path) { return destination.path }
        guard let (base, token) = await serverAccess() else { return nil }
        do {
            try await PlexAPI().downloadPoster(thumb, base: base, token: token, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }
}
