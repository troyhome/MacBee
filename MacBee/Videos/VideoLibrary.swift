import Foundation
import MacBeeVideo
import Observation

/// The Videos section's data: the catalog of movies, shows and music videos (saved between launches and
/// re-scanned in the background), likes, and how far each video was watched. Likes and positions are per Mac.
@MainActor
@Observable
final class VideoLibrary {
    private(set) var catalog = VideoCatalogStore.load() ?? VideoCatalog()
    private(set) var isScanning = false
    /// Liked movies (their file path), shows (their folder) and music videos (their file path).
    private(set) var liked: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "likedVideos") ?? [])
    /// Seconds watched, per file path, for "Continue Watching" and Resume.
    private(set) var positions: [String: Double] = UserDefaults.standard.dictionary(forKey: "videoPositions") as? [String: Double] ?? [:]
    /// When each movie, show or music video (by its id) was last started, for Recently Played.
    private(set) var lastPlayed: [String: Date] = UserDefaults.standard.dictionary(forKey: "videoLastPlayed") as? [String: Date] ?? [:]
    /// Files watched to the end.
    private(set) var watched: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "watchedVideos") ?? [])

    /// Looks through the video folders (movies and shows) and music folders (music videos) again.
    func refresh(videoFolders: [URL], musicFolders: [URL], plex: PlexConnection?) async {
        guard !isScanning else { return }
        isScanning = true
        let roots = videoFolders.map { VideoScanner.Root(url: $0, kind: .moviesAndShows) }
            + musicFolders.map { VideoScanner.Root(url: $0, kind: .musicVideos) }
        let reachable = roots.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        let previous = catalog
        var found = await Task.detached(priority: .utility) { VideoScanner.scan(reachable) }.value
        // Fresh details from Plex when it can be reached; otherwise the ones saved last time.
        var index = PlexVideoIndex.loadSaved()
        if let plex, let fresh = await plex.videoIndex() {
            index = await Self.downloadPosters(for: found, in: fresh, plex: plex)
            index?.save()
        }
        if let index { found = Self.enrich(found, with: index) }
        found = Self.removingExcluded(from: found)
        // A drive that's away keeps its videos listed until it's back.
        if reachable.count == roots.count || !found.isEmpty || previous.isEmpty {
            catalog = found
            VideoCatalogStore.save(found)
        }
        isScanning = false
    }

    /// Downloads (or reuses) the Plex posters of the videos found, and notes where each was saved.
    private static func downloadPosters(for catalog: VideoCatalog, in index: PlexVideoIndex,
                                        plex: PlexConnection) async -> PlexVideoIndex {
        var index = index
        let movieFiles = catalog.movies.flatMap(\.files).map { PlexVideoIndex.fileName($0.path) }
        for name in movieFiles {
            guard var info = index.movies[name], info.posterPath == nil, let thumb = info.thumb else { continue }
            info.posterPath = await plex.posterFile(for: thumb)
            index.movies[name] = info
        }
        // One episode per show is enough to find the show's poster.
        for show in catalog.shows {
            guard let name = show.seasons.flatMap(\.episodes).map({ PlexVideoIndex.fileName($0.file.path) })
                .first(where: { index.shows[$0] != nil }),
                  var info = index.shows[name], info.posterPath == nil, let thumb = info.thumb else { continue }
            info.posterPath = await plex.posterFile(for: thumb)
            for episode in show.seasons.flatMap(\.episodes) {
                let key = PlexVideoIndex.fileName(episode.file.path)
                if index.shows[key] != nil { index.shows[key]?.posterPath = info.posterPath }
            }
        }
        return index
    }

    /// Fills in proper titles, years, genres, descriptions and posters from Plex for videos it knows.
    private static func enrich(_ catalog: VideoCatalog, with index: PlexVideoIndex) -> VideoCatalog {
        var catalog = catalog
        for i in catalog.movies.indices {
            guard let info = catalog.movies[i].files.lazy.compactMap({ index.movies[PlexVideoIndex.fileName($0.path)] }).first
            else { continue }
            if !info.title.isEmpty { catalog.movies[i].title = info.title }
            if let year = info.year { catalog.movies[i].year = year }
            if !info.genres.isEmpty { catalog.movies[i].genres = info.genres }
            catalog.movies[i].summary = info.summary
            if catalog.movies[i].posterPath == nil { catalog.movies[i].posterPath = existing(info.posterPath) }
        }
        for i in catalog.shows.indices {
            let files = catalog.shows[i].seasons.flatMap(\.episodes).map(\.file.path)
            guard let info = files.lazy.compactMap({ index.shows[PlexVideoIndex.fileName($0)] }).first else { continue }
            if !info.title.isEmpty { catalog.shows[i].title = info.title }
            if let year = info.year { catalog.shows[i].year = year }
            if !info.genres.isEmpty { catalog.shows[i].genres = info.genres }
            catalog.shows[i].summary = info.summary
            let poster = files.lazy.compactMap { index.shows[PlexVideoIndex.fileName($0)]?.posterPath }.first
            if catalog.shows[i].posterPath == nil { catalog.shows[i].posterPath = existing(poster) }
        }
        catalog.movies.sort { VideoScanner.sortKey($0.title) < VideoScanner.sortKey($1.title) }
        catalog.shows.sort { VideoScanner.sortKey($0.title) < VideoScanner.sortKey($1.title) }
        return catalog
    }

    private static func existing(_ path: String?) -> String? {
        path.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    // MARK: - Copies removed from the Videos library (Duplicates page)

    /// Video files taken out of MacBee (they stay on disk), by path. Saved on this Mac.
    private(set) var excluded: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "excludedVideos") ?? [])

    func setExcluded(_ paths: [String], _ isExcluded: Bool) {
        if isExcluded { excluded.formUnion(paths) } else { excluded.subtract(paths) }
        UserDefaults.standard.set(Array(excluded).sorted(), forKey: "excludedVideos")
        catalog = Self.removingExcluded(from: catalog)
        VideoCatalogStore.save(catalog)
    }

    /// Brings back every removed copy (the folders are searched again to find them).
    func restoreExcluded() {
        excluded = []
        UserDefaults.standard.removeObject(forKey: "excludedVideos")
    }

    /// Drops removed copies; a video whose shown copy was removed shows its next copy instead.
    private static func removingExcluded(from catalog: VideoCatalog) -> VideoCatalog {
        let excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedVideos") ?? [])
        guard !excluded.isEmpty else { return catalog }
        var catalog = catalog
        catalog.movies = catalog.movies.compactMap { movie in
            var movie = movie
            movie.files.removeAll { excluded.contains($0.path) }
            return movie.files.isEmpty ? nil : movie
        }
        catalog.musicVideos = catalog.musicVideos.compactMap { video in
            let files = video.allFiles.filter { !excluded.contains($0.path) }
            guard let first = files.first else { return nil }
            var video = video
            video.file = first
            video.otherFiles = Array(files.dropFirst())
            return video
        }
        return catalog
    }

    // MARK: - Likes

    func isLiked(_ id: String) -> Bool { liked.contains(id) }

    func toggleLike(_ id: String) {
        if liked.remove(id) == nil { liked.insert(id) }
        UserDefaults.standard.set(Array(liked).sorted(), forKey: "likedVideos")
    }

    // MARK: - Watching

    func markPlayed(_ id: String) {
        lastPlayed[id] = Date()
        UserDefaults.standard.set(lastPlayed, forKey: "videoLastPlayed")
    }

    func position(of path: String) -> Double { positions[path] ?? 0 }

    /// Saves where a video was stopped. Near the start counts as not started, near the end as watched.
    func savePosition(_ seconds: Double, duration: Double, for path: String) {
        if duration > 0 && seconds > duration - max(60, duration * 0.05) {
            positions[path] = nil
            watched.insert(path)
            UserDefaults.standard.set(Array(watched), forKey: "watchedVideos")
        } else if seconds > 30 {
            positions[path] = seconds
        } else {
            positions[path] = nil
        }
        UserDefaults.standard.set(positions, forKey: "videoPositions")
    }

    /// Movies and episodes stopped part-way through, most recently added first.
    var continueWatching: [VideoTitle] {
        let started = Set(positions.keys)
        guard !started.isEmpty else { return [] }
        let movies = catalog.movies.filter { movie in movie.files.contains { started.contains($0.path) } }.map(VideoTitle.movie)
        let shows = catalog.shows.filter { show in
            show.seasons.contains { $0.episodes.contains { started.contains($0.file.path) } }
        }.map(VideoTitle.show)
        return movies + shows
    }

    // MARK: - Lists for the pages

    var allTitles: [VideoTitle] {
        catalog.movies.map(VideoTitle.movie) + catalog.shows.map(VideoTitle.show)
    }

    func titles(in category: VideoCategory, genre: String?, matching text: String) -> [VideoTitle] {
        var titles: [VideoTitle]
        switch category {
        case .recentlyPlayed:
            titles = (allTitles + catalog.musicVideos.map(VideoTitle.musicVideo))
                .compactMap { title in lastPlayed[title.id].map { (title, $0) } }
                .sorted { $0.1 > $1.1 }
                .prefix(60).map(\.0)
        case .movies: titles = catalog.movies.map(VideoTitle.movie)
        case .shows: titles = catalog.shows.map(VideoTitle.show)
        case .musicVideos: titles = catalog.musicVideos.map(VideoTitle.musicVideo)
        case .genres: titles = genre.map { genre in allTitles.filter { $0.genres.contains(genre) } } ?? []
        case .liked: titles = (allTitles + catalog.musicVideos.map(VideoTitle.musicVideo)).filter { liked.contains($0.id) }
        }
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return titles }
        return titles.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// The episode after this one (next in the season, or the first of the next season).
    func episode(after episode: Episode, in show: Show) -> Episode? {
        let all = show.seasons.flatMap(\.episodes)
        guard let index = all.firstIndex(where: { $0.id == episode.id }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// Where Play starts a show: the episode in progress, else the first one not yet watched.
    func nextEpisode(in show: Show) -> Episode? {
        let all = show.seasons.flatMap(\.episodes)
        return all.first { positions[$0.file.path] != nil } ?? all.first { !watched.contains($0.file.path) } ?? all.first
    }
}
