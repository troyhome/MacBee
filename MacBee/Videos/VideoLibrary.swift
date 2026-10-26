import Foundation
import MacBeeLibrary
import MacBeeVideo
import Observation

/// The Videos section's data: the catalog of movies, shows and music videos (saved between launches and
/// re-scanned in the background), likes, and how far each video was watched. Likes travel to your other Macs with
/// Sync (by file or folder name, since drive paths differ); positions stay per Mac.
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
    /// When each file was last watched, and how long it runs, for Continue Watching (order and time left).
    private(set) var lastWatched: [String: Date] = UserDefaults.standard.dictionary(forKey: "videoLastWatched") as? [String: Date] ?? [:]
    private(set) var durations: [String: Double] = UserDefaults.standard.dictionary(forKey: "videoDurations") as? [String: Double] ?? [:]
    /// Shows whose "Up Next" card was removed, and when; it comes back once the show is watched again.
    private(set) var upNextDismissed: [String: Date] = UserDefaults.standard.dictionary(forKey: "videoUpNextDismissed") as? [String: Date] ?? [:]

    /// Each folder's file list from its last walk, so a single folder can be scanned again on its own.
    @ObservationIgnored private let fileCache = VideoFileCache()

    /// Looks through the video folders (movies and shows) and music folders (music videos) again.
    /// With `only`, just that folder is walked again; the others reuse what was found last time.
    func refresh(videoFolders: [URL], musicFolders: [URL], plex: PlexConnection?, only: URL? = nil) async {
        guard !isScanning else { return }
        isScanning = true
        let roots = videoFolders.map { VideoScanner.Root(url: $0, kind: .moviesAndShows) }
            + musicFolders.map { VideoScanner.Root(url: $0, kind: .musicVideos) }
        let reachable = roots.filter {
            FileManager.default.fileExists(atPath: $0.url.path) && !VolumeLocation.isLeftoverMountPoint($0.url.path)
        }
        let previous = catalog
        let cache = fileCache
        let refreshing = only.map { Set([$0.path]) }
        var found = await Task.detached(priority: .utility) {
            VideoScanner.scan(reachable, cache: cache, refreshing: refreshing)
        }.value
        // Fresh details from Plex when it can be reached; otherwise the ones saved last time.
        var index = PlexVideoIndex.loadSaved()
        if let plex, let fresh = await plex.videoIndex() {
            index = await Self.downloadPosters(for: found, in: fresh, plex: plex)
            index?.save()
        }
        if let index { found = Self.enrich(found, with: index) }
        // The music folders weren't known yet (MacBee still starting) or none could be reached:
        // keep the music videos found last time instead of emptying the list.
        if found.musicVideos.isEmpty && !previous.musicVideos.isEmpty
            && !reachable.contains(where: { $0.kind == .musicVideos }) {
            found.musicVideos = previous.musicVideos
        }
        found = Self.removingExcluded(from: found)
        // A drive that's away keeps its videos listed until it's back.
        if reachable.count == roots.count || !found.isEmpty || previous.isEmpty {
            catalog = found
            VideoCatalogStore.save(found)
            setSyncedLikes(syncedLikeKeys) // likes that arrived before these videos were found
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
        for s in catalog.shows.indices {
            for n in catalog.shows[s].seasons.indices {
                catalog.shows[s].seasons[n].episodes = catalog.shows[s].seasons[n].episodes.compactMap { episode in
                    let files = episode.allFiles.filter { !excluded.contains($0.path) }
                    guard let first = files.first else { return nil }
                    var episode = episode
                    episode.file = first
                    episode.otherFiles = files.count > 1 ? Array(files.dropFirst()) : nil
                    return episode
                }
            }
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

    // MARK: - Likes on other Macs

    /// Likes from other Macs not yet matched to a video here (that drive may not be scanned yet).
    private var unmatchedLikeKeys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "unmatchedVideoLikes") ?? [])

    /// A like's name on every Mac: the file name (movies, music videos) or folder name (shows), lowercased.
    static func syncKey(_ id: String) -> String { (id as NSString).lastPathComponent.lowercased() }

    /// Every name a liked id could arrive under (a movie's other copies count too).
    private var idsByKey: [String: [String]] {
        var ids: [String: [String]] = [:]
        for movie in catalog.movies {
            for file in movie.files { ids[Self.syncKey(file.path), default: []].append(movie.id) }
        }
        for show in catalog.shows { ids[Self.syncKey(show.id), default: []].append(show.id) }
        for video in catalog.musicVideos {
            for file in video.allFiles { ids[Self.syncKey(file.path), default: []].append(video.id) }
        }
        return ids
    }

    /// The likes to send to another Mac.
    var syncedLikeKeys: [String] { Set(liked.map(Self.syncKey)).union(unmatchedLikeKeys).sorted() }

    /// Makes the likes here exactly `keys` (after a sync). Returns how many likes were added and removed.
    @discardableResult
    func setSyncedLikes(_ keys: [String]) -> Int {
        let wanted = Set(keys)
        let ids = idsByKey
        var updated = liked.filter { wanted.contains(Self.syncKey($0)) }
        var matched = Set<String>()
        for key in wanted { if let found = ids[key] { updated.formUnion(found); matched.insert(key) } }
        matched.formUnion(updated.map(Self.syncKey))
        let changes = updated.symmetricDifference(liked).count
        liked = updated
        unmatchedLikeKeys = wanted.subtracting(matched)
        UserDefaults.standard.set(Array(liked).sorted(), forKey: "likedVideos")
        UserDefaults.standard.set(Array(unmatchedLikeKeys).sorted(), forKey: "unmatchedVideoLikes")
        return changes
    }

    // MARK: - A drive mounted somewhere else

    /// A video or music folder's drive is now mounted at `newRoot` instead of `oldRoot`: likes, places, watched
    /// marks and removed copies kept by file path follow it.
    func moveRoot(from oldRoot: String, to newRoot: String) {
        func moved(_ key: String) -> String {
            key == oldRoot || key.hasPrefix(oldRoot + "/") ? newRoot + key.dropFirst(oldRoot.count) : key
        }
        func movedKeys<V>(_ dict: [String: V]) -> [String: V] {
            Dictionary(dict.map { (moved($0.key), $0.value) }, uniquingKeysWith: { _, new in new })
        }
        liked = Set(liked.map(moved)); UserDefaults.standard.set(Array(liked).sorted(), forKey: "likedVideos")
        watched = Set(watched.map(moved)); UserDefaults.standard.set(Array(watched), forKey: "watchedVideos")
        excluded = Set(excluded.map(moved)); UserDefaults.standard.set(Array(excluded).sorted(), forKey: "excludedVideos")
        positions = movedKeys(positions); UserDefaults.standard.set(positions, forKey: "videoPositions")
        lastPlayed = movedKeys(lastPlayed); UserDefaults.standard.set(lastPlayed, forKey: "videoLastPlayed")
        lastWatched = movedKeys(lastWatched); UserDefaults.standard.set(lastWatched, forKey: "videoLastWatched")
        durations = movedKeys(durations); UserDefaults.standard.set(durations, forKey: "videoDurations")
        upNextDismissed = movedKeys(upNextDismissed); UserDefaults.standard.set(upNextDismissed, forKey: "videoUpNextDismissed")
    }

    // MARK: - Syncing watching progress (Device Sync)

    /// Every file path and title id under each sync key (file or folder name, lowercased).
    private var pathsByKey: [String: [String]] {
        var paths: [String: [String]] = [:]
        func add(_ path: String) { paths[Self.syncKey(path), default: []].append(path) }
        for movie in catalog.movies { movie.files.forEach { add($0.path) } }
        for show in catalog.shows {
            add(show.id)
            show.seasons.flatMap(\.episodes).flatMap(\.allFiles).forEach { add($0.path) }
        }
        for video in catalog.musicVideos { video.allFiles.forEach { add($0.path) } }
        return paths
    }

    /// Where each video was stopped and when it was watched, to send to another Mac.
    var syncedWatching: [ProfileSnapshot.VideoWatchState] {
        let keys = Set(positions.keys).union(lastWatched.keys).union(watched).union(lastPlayed.keys)
        var states: [String: ProfileSnapshot.VideoWatchState] = [:]
        for path in keys {
            let key = Self.syncKey(path)
            var state = states[key] ?? .init(key: key, position: nil, duration: nil, lastWatched: nil, lastPlayed: nil, watched: false)
            state.position = state.position ?? positions[path]
            state.duration = state.duration ?? durations[path]
            state.lastWatched = [state.lastWatched, lastWatched[path]].compactMap { $0 }.max()
            state.lastPlayed = [state.lastPlayed, lastPlayed[path]].compactMap { $0 }.max()
            state.watched = state.watched || watched.contains(path)
            states[key] = state
        }
        return states.values.sorted { $0.key < $1.key }
    }

    /// Takes in another Mac's watching progress: where it was watched more recently, its spot wins.
    /// Returns how many videos changed.
    @discardableResult
    func mergeWatching(_ theirs: [ProfileSnapshot.VideoWatchState]) -> Int {
        let paths = pathsByKey
        var changed = Set<String>()
        for state in theirs {
            for path in paths[state.key] ?? [] {
                if let when = state.lastWatched, when > (lastWatched[path] ?? .distantPast) {
                    lastWatched[path] = when
                    positions[path] = state.watched && state.position == nil ? nil : (state.position ?? positions[path])
                    changed.insert(path)
                }
                if let duration = state.duration, durations[path] == nil { durations[path] = duration }
                if state.watched, !watched.contains(path), state.position == nil {
                    watched.insert(path)
                    changed.insert(path)
                }
                if let when = state.lastPlayed, when > (lastPlayed[path] ?? .distantPast) {
                    lastPlayed[path] = when
                    changed.insert(path)
                }
            }
        }
        if !changed.isEmpty {
            UserDefaults.standard.set(positions, forKey: "videoPositions")
            UserDefaults.standard.set(lastWatched, forKey: "videoLastWatched")
            UserDefaults.standard.set(durations, forKey: "videoDurations")
            UserDefaults.standard.set(Array(watched), forKey: "watchedVideos")
            UserDefaults.standard.set(lastPlayed, forKey: "videoLastPlayed")
        }
        return changed.count
    }

    // MARK: - Watching

    func markPlayed(_ id: String) {
        lastPlayed[id] = Date()
        UserDefaults.standard.set(lastPlayed, forKey: "videoLastPlayed")
    }

    func position(of path: String) -> Double { positions[path] ?? 0 }

    /// Saves where a video was stopped. Near the start counts as not started, near the end as watched.
    /// A video watched at least this long shows in Continue Watching (Troy: stopping early should still count).
    static let continueAfter: Double = 5

    func savePosition(_ seconds: Double, duration: Double, for path: String) {
        if duration > 0 {
            durations[path] = duration
            UserDefaults.standard.set(durations, forKey: "videoDurations")
        }
        if seconds >= Self.continueAfter {
            lastWatched[path] = Date()
            UserDefaults.standard.set(lastWatched, forKey: "videoLastWatched")
        }
        if duration > 0 && seconds > duration - max(60, duration * 0.05) {
            positions[path] = nil
            watched.insert(path)
            UserDefaults.standard.set(Array(watched), forKey: "watchedVideos")
        } else if seconds >= Self.continueAfter {
            positions[path] = seconds
        } else {
            positions[path] = nil
        }
        UserDefaults.standard.set(positions, forKey: "videoPositions")
    }

    /// Takes a card off Continue Watching: forgets the position, or hides a show's Up Next until it's watched again.
    func removeFromContinueWatching(_ item: ContinueItem) {
        if item.isUpNext, case let .episode(_, show) = item.kind {
            upNextDismissed[show.id] = Date()
            UserDefaults.standard.set(upNextDismissed, forKey: "videoUpNextDismissed")
        } else {
            positions[item.file.path] = nil
            UserDefaults.standard.set(positions, forKey: "videoPositions")
        }
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
        if let item = continueItem(for: show), case let .episode(episode, _) = item.kind { return episode }
        return all.first { positions[$0.file.path] != nil } ?? all.first { !watched.contains($0.file.path) } ?? all.first
    }
}
