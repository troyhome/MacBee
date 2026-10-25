import Foundation

/// Pairs songs on a Subsonic server (Navidrome, Gonic, Airsonic…) with songs in the library, so a song can be
/// fetched from the server when the network drive can't be reached.
///
/// Servers that report real file paths are matched by path, like Plex. Navidrome reports made-up paths unless
/// "Report Real Path" is on, so the rest are matched by artist, title and album, with lengths within 2 seconds.
public enum SubsonicMatcher {
    public struct RemoteSong: Sendable, Equatable {
        public var id: String
        public var path: String?
        public var artist: String?
        public var title: String?
        public var album: String?
        public var duration: Double?
        public init(id: String, path: String?, artist: String?, title: String?, album: String?, duration: Double?) {
            self.id = id
            self.path = path
            self.artist = artist
            self.title = title
            self.album = album
            self.duration = duration
        }
    }

    public struct LocalSong: Sendable, Equatable {
        public var trackId: Int64
        /// Path inside its library folder, e.g. "Artist/Album/01.flac".
        public var relativePath: String
        public var artist: String
        public var title: String
        public var album: String
        public var duration: Double
        public init(trackId: Int64, relativePath: String, artist: String, title: String, album: String, duration: Double) {
            self.trackId = trackId
            self.relativePath = relativePath
            self.artist = artist
            self.title = title
            self.album = album
            self.duration = duration
        }
    }

    /// Track id -> server song id for every song found in both places.
    public static func match(remote: [RemoteSong], local: [LocalSong]) -> [Int64: String] {
        // 1. By path (servers that report real paths).
        let withPaths = remote.compactMap { song in song.path.map { PlexMatcher.PlexFile(path: $0, partKey: song.id) } }
        var result = PlexMatcher.match(plexFiles: withPaths,
                                       localFiles: local.map { .init(trackId: $0.trackId, relativePath: $0.relativePath) })

        // 2. By tags, for the rest.
        var byTags: [String: [LocalSong]] = [:]
        let matchedIds = Set(result.keys)
        for song in local where !matchedIds.contains(song.trackId) {
            byTags[key(song.artist, song.title, song.album), default: []].append(song)
        }
        let usedRemote = Set(result.values)
        for song in remote where !usedRemote.contains(song.id) {
            guard let title = song.title else { continue }
            let k = key(song.artist ?? "", title, song.album ?? "")
            guard var candidates = byTags[k], !candidates.isEmpty else { continue }
            let index = candidates.firstIndex { local in
                guard let length = song.duration else { return true }
                return abs(local.duration - length) <= DuplicateFinder.durationTolerance
            }
            guard let index else { continue }
            result[candidates[index].trackId] = song.id
            candidates.remove(at: index)
            byTags[k] = candidates
        }
        return result
    }

    static func key(_ artist: String, _ title: String, _ album: String) -> String {
        [artist, title, album].map(DuplicateFinder.fingerprint).joined(separator: "|")
    }
}
