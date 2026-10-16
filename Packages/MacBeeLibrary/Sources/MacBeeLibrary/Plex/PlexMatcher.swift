import Foundation

/// Pairs files on a Plex server with songs in the library by their path, so a song can be played from Plex
/// when the network drive can't be reached.
///
/// Plex sees the same files under a different starting folder (e.g. "/volume1/2 Set Music/Artist/Album/01.flac"
/// for "/Volumes/2 Set Music/Artist/Album/01.flac"), so paths are compared from the music folder down,
/// ignoring capitals and differences in how accented letters are stored.
public enum PlexMatcher {
    public struct PlexFile: Sendable, Equatable {
        public var path: String
        public var partKey: String
        public init(path: String, partKey: String) {
            self.path = path
            self.partKey = partKey
        }
    }

    public struct LocalFile: Sendable, Equatable {
        public var trackId: Int64
        /// Path inside its library folder, e.g. "Artist/Album/01.flac".
        public var relativePath: String
        public init(trackId: Int64, relativePath: String) {
            self.trackId = trackId
            self.relativePath = relativePath
        }
    }

    /// Track id -> Plex part key for every file found in both places.
    public static func match(plexFiles: [PlexFile], localFiles: [LocalFile]) -> [Int64: String] {
        var local: [String: Int64] = [:]
        for file in localFiles { local[normalize(file.relativePath)] = file.trackId }

        var result: [Int64: String] = [:]
        var knownPrefixes: [Int: Int] = [:] // components to drop -> how often it worked
        for file in plexFiles {
            let parts = normalize(file.path).split(separator: "/").map(String.init)
            // Try the drop count that has worked most often first, then all others (shortest prefix first).
            let preferred = knownPrefixes.max { $0.value < $1.value }?.key
            let order = (preferred.map { [$0] } ?? []) + Array(0..<parts.count).filter { $0 != preferred }
            for drop in order where drop < parts.count {
                let candidate = parts[drop...].joined(separator: "/")
                if let id = local[candidate] {
                    result[id] = file.partKey
                    knownPrefixes[drop, default: 0] += 1
                    break
                }
            }
        }
        return result
    }

    static func normalize(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
