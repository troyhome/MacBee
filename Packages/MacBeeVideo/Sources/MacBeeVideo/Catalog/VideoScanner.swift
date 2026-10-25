import Foundation

/// Walks the video folders and builds the catalog: movies, TV shows (grouped by show and season)
/// and music videos. Uses only file and folder names plus artwork and .nfo files sitting next to the videos.
public enum VideoScanner {
    public struct Root: Sendable {
        public var url: URL
        public var kind: VideoFolderKind
        public init(url: URL, kind: VideoFolderKind) {
            self.url = url
            self.kind = kind
        }
    }

    /// Smaller files are trailers, samples or extras.
    static let minimumSize: Int64 = 20_000_000
    /// Folders whose contents are extras, not the film itself.
    static let skippedFolders: Set<String> = ["extras", "featurettes", "behind the scenes", "deleted scenes",
                                              "trailers", "samples", "sample", "interviews", "shorts"]

    /// `cache` keeps each folder's file list between scans; with `refreshing`, only those folders (paths as given in
    /// `roots`) are walked again and the others reuse their last list. Without a cache every folder is walked.
    public static func scan(_ roots: [Root], cache: VideoFileCache? = nil, refreshing: Set<String>? = nil) -> VideoCatalog {
        var movies: [String: Movie] = [:]
        var shows: [String: Show] = [:]
        var musicVideos: [MusicVideo] = []
        var musicVideoIndex: [String: Int] = [:]
        /// Which folder each file came from (0 = first). Folders come in priority order, like music folders:
        /// the same movie or episode in a later folder only fills in what the earlier ones don't have.
        var rank: [String: Int] = [:]

        for (index, root) in roots.enumerated() {
            // Resolved, so paths from the walk line up with it (/var vs /private/var, symlinked drives).
            let rootURL = root.url.resolvingSymlinksInPath()
            let walkAgain = refreshing.map { $0.contains(root.url.path) } ?? true
            let files = cache?.files(in: rootURL, walkAgain: walkAgain) ?? videoFiles(in: rootURL)
            for found in files {
                rank[found.file.path] = index
                switch root.kind {
                case .musicVideos:
                    // The same video in another music folder (a second drive) shows once: the first folder wins,
                    // and folders come in priority order.
                    let key = VideoScanner.sortKey(found.url.deletingPathExtension().lastPathComponent)
                    if let index = musicVideoIndex[key] {
                        musicVideos[index].otherFiles = (musicVideos[index].otherFiles ?? []) + [found.file]
                        continue
                    }
                    musicVideoIndex[key] = musicVideos.count
                    musicVideos.append(MusicVideo(title: found.url.deletingPathExtension().lastPathComponent,
                                                  folderName: found.url.deletingLastPathComponent().lastPathComponent,
                                                  file: found.file))
                case .moviesAndShows:
                    add(found, root: rootURL, movies: &movies, shows: &shows)
                }
            }
        }

        // The copy shown: from the first folder that has it, then 4K before HD, then the largest.
        func better(_ a: VideoFile, _ b: VideoFile) -> Bool {
            let (ra, rb) = (rank[a.path] ?? 0, rank[b.path] ?? 0)
            if ra != rb { return ra < rb }
            return (a.is4K ? 1 : 0, a.size) > (b.is4K ? 1 : 0, b.size)
        }

        var catalog = VideoCatalog()
        catalog.movies = mergingYearless(Array(movies.values)).map { movie in
            var movie = movie
            movie.files.sort(by: better)
            return movie
        }.sorted { sortKey($0.title) < sortKey($1.title) }
        catalog.shows = shows.values.map { show in
            var show = show
            show.seasons = show.seasons.map { season in
                // One entry per episode: the same episode found in several folders shows once.
                var byNumber: [Int: [Episode]] = [:]
                for episode in season.episodes { byNumber[episode.number, default: []].append(episode) }
                var season = season
                season.episodes = byNumber.values.map { copies in
                    let ordered = copies.sorted { better($0.file, $1.file) }
                    var episode = ordered[0]
                    let others = ordered.dropFirst().map(\.file)
                    episode.otherFiles = others.isEmpty ? nil : Array(others)
                    if episode.title == nil { episode.title = ordered.compactMap(\.title).first }
                    return episode
                }.sorted { $0.number < $1.number }
                return season
            }.sorted { $0.number < $1.number }
            return show
        }.sorted { sortKey($0.title) < sortKey($1.title) }
        catalog.musicVideos = musicVideos.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        catalog.scannedAt = Date()
        return catalog
    }

    // MARK: - Sorting movies and shows

    private static func add(_ found: FoundFile, root: URL, movies: inout [String: Movie], shows: inout [String: Show]) {
        let fileName = found.url.deletingPathExtension().lastPathComponent
        let folder = found.url.deletingLastPathComponent()
        let rootComponents = comparable(root).pathComponents
        let relative = Array(comparable(found.url).pathComponents.dropFirst(rootComponents.count))
        let topFolder = relative.count > 1 ? root.appendingPathComponent(relative[0]) : nil

        if let marker = VideoNameParser.episode(in: fileName) {
            // An episode. The show is the top folder under the video folder (or the file name before the marker).
            let showName = showTitle(from: topFolder?.lastPathComponent ?? fileName)
            // Same title, different years are different shows (Scrubs 2001 and Scrubs 2026).
            let key = "\(showName.title.lowercased())|\(showName.year.map(String.init) ?? "")"
            let showFolder = topFolder ?? folder
            var show = shows[key] ?? Show(title: showName.title, year: showName.year, folderPath: showFolder.path,
                                          posterPath: nil, genres: [], seasons: [])
            if show.year == nil { show.year = showName.year }
            if show.posterPath == nil { show.posterPath = artwork(in: showFolder, baseName: nil, anyImage: true) }
            if show.genres.isEmpty { show.genres = genres(in: showFolder, names: ["tvshow.nfo"]) }
            let episode = Episode(season: marker.season, number: marker.episode,
                                  title: episodeTitle(marker.rest, showTitle: showName.title), file: found.file)
            if let index = show.seasons.firstIndex(where: { $0.number == marker.season }) {
                show.seasons[index].episodes.append(episode)
            } else {
                show.seasons.append(Season(number: marker.season, episodes: [episode]))
            }
            shows[key] = show
            return
        }

        // A movie. The file name usually has the title and year; fall back to the folder's name.
        var name = VideoNameParser.name(from: fileName)
        if comparable(folder) != comparable(root) {
            let folderName = VideoNameParser.name(from: folder.lastPathComponent)
            if name.year == nil && folderName.year != nil || name.title.isEmpty { name = folderName }
        }
        guard !name.title.isEmpty else { return }
        let key = "\(name.title.lowercased())|\(name.year.map(String.init) ?? "")"
        var movie = movies[key] ?? Movie(title: name.title, year: name.year, files: [], posterPath: nil, genres: [])
        movie.files.append(found.file)
        if movie.posterPath == nil {
            movie.posterPath = artwork(in: folder, baseName: fileName, anyImage: comparable(folder) != comparable(root))
        }
        if movie.genres.isEmpty { movie.genres = genres(in: folder, names: ["\(fileName).nfo", "movie.nfo"]) }
        movies[key] = movie
    }

    /// A movie found without a year in one folder ("Heat.mkv") and with one in another ("Heat (1995)") is the
    /// same film when there's only one film by that title.
    static func mergingYearless(_ movies: [Movie]) -> [Movie] {
        var byTitle: [String: [Int]] = [:]
        for (index, movie) in movies.enumerated() { byTitle[movie.title.lowercased(), default: []].append(index) }
        var merged = movies
        var dropped = Set<Int>()
        for indices in byTitle.values where indices.count > 1 {
            let dated = indices.filter { movies[$0].year != nil }
            let undated = indices.filter { movies[$0].year == nil }
            guard dated.count == 1, let target = dated.first else { continue }
            for index in undated {
                merged[target].files += movies[index].files
                if merged[target].posterPath == nil { merged[target].posterPath = movies[index].posterPath }
                if merged[target].genres.isEmpty { merged[target].genres = movies[index].genres }
                dropped.insert(index)
            }
        }
        return merged.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
    }

    /// The same folder can show up as /var/… and /private/var/…; compare without the /private.
    static func comparable(_ url: URL) -> URL {
        let path = url.standardizedFileURL.path
        return URL(fileURLWithPath: path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path)
    }

    /// "Friends.Complete.Series.720p…", "A.P.Bio.S02.COMPLETE…", "Community S1", "Scrubs (2026)".
    static func showTitle(from raw: String) -> VideoNameParser.Name {
        var text = VideoNameParser.spaced(raw)
        if let range = text.range(of: #"(?i)\b(s\d{1,2}(e\d{1,3})?|season\s*\d+|\d{1,2}x\d{2,3})\b"#, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        text = text.replacingOccurrences(of: #"(?i)\bcomplete( series)?\b"#, with: " ", options: .regularExpression)
        return VideoNameParser.name(from: text)
    }

    /// The episode title, unless it's just the show's name again.
    static func episodeTitle(_ rest: String?, showTitle: String) -> String? {
        guard let rest, !rest.isEmpty else { return nil }
        let cleaned = rest.hasPrefix(showTitle) ? String(rest.dropFirst(showTitle.count)) : rest
        let tidy = VideoNameParser.tidy(cleaned)
        return tidy.isEmpty ? nil : tidy
    }

    /// "The Big Lebowski" sorts under B.
    public static func sortKey(_ title: String) -> String {
        var key = title.lowercased()
        for article in ["the ", "a ", "an "] where key.hasPrefix(article) {
            key.removeFirst(article.count)
            break
        }
        return key
    }

    // MARK: - Files on disk

    struct FoundFile {
        var url: URL
        var file: VideoFile
    }

    static func videoFiles(in root: URL) -> [FoundFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .creationDateKey,
                                      .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var result: [FoundFile] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skippedFolders.contains(url.lastPathComponent.lowercased()) { walker.skipDescendants() }
                continue
            }
            let name = url.lastPathComponent
            guard values?.isRegularFile == true,
                  VideoNameParser.videoExtensions.contains(url.pathExtension.lowercased()),
                  !VideoNameParser.isSample(name) else { continue }
            let size = Int64(values?.fileSize ?? 0)
            guard size >= minimumSize else { continue }
            // Quality tags may sit on the folder ("Lawrence of Arabia (1962)/… [2160p] [4K] …mkv" or the other way round).
            let tags = url.deletingLastPathComponent().lastPathComponent + " " + name
            let file = VideoFile(path: url.path, size: size,
                                 added: values?.creationDate ?? values?.contentModificationDate ?? .distantPast,
                                 is4K: VideoNameParser.is4K(tags), isHDR: VideoNameParser.isHDR(tags))
            result.append(FoundFile(url: url, file: file))
        }
        return result
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]
    static let notPosters = ["backdrop", "landscape", "logo", "fanart", "banner", "thumb", "clearart", "disc", "background"]

    /// A poster next to the video: "<name>-poster.jpg", "<name>.jpg", poster/folder/cover.jpg, or (in its own
    /// folder) any picture that isn't a backdrop or logo.
    static func artwork(in folder: URL, baseName: String?, anyImage: Bool) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let images = names.filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        func find(_ stem: String) -> String? {
            images.first { ($0 as NSString).deletingPathExtension.lowercased() == stem.lowercased() }
        }
        var candidates: [String?] = []
        if let baseName { candidates += [find("\(baseName)-poster"), find(baseName)] }
        candidates += [find("poster"), find("folder"), find("cover")]
        if anyImage {
            candidates.append(images.first { name in
                let lower = name.lowercased()
                return !notPosters.contains(where: lower.contains)
            })
        }
        return candidates.compactMap { $0 }.first.map { folder.appendingPathComponent($0).path }
    }

    /// <genre> entries from a Kodi/Jellyfin style .nfo file next to the video.
    static func genres(in folder: URL, names: [String]) -> [String] {
        for name in names {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { continue }
            let regex = try? NSRegularExpression(pattern: "<genre>([^<]+)</genre>")
            let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            let found = matches.compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) } }
            if !found.isEmpty { return Array(NSOrderedSet(array: found)) as? [String] ?? found }
        }
        return []
    }
}

/// Each video folder's file list from its last walk, so one folder can be looked through again on its own.
public final class VideoFileCache: @unchecked Sendable {
    private let lock = NSLock()
    private var lists: [String: [VideoScanner.FoundFile]] = [:]

    public init() {}

    func files(in root: URL, walkAgain: Bool) -> [VideoScanner.FoundFile] {
        if !walkAgain, let cached = lock.withLock({ lists[root.path] }) { return cached }
        let found = VideoScanner.videoFiles(in: root)
        lock.withLock { lists[root.path] = found }
        return found
    }
}
