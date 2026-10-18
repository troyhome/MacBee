import Foundation

/// Finds copies of the same song (same artist, title and album, lengths within 2 seconds of each other)
/// and picks the one to show: from the highest-priority folder, then the best quality. Pure logic, unit-tested.
public enum DuplicateFinder {
    public struct Song: Sendable, Equatable {
        public var id: Int64
        public var artist: String
        public var title: String
        public var album: String
        public var duration: Double
        /// The folder's priority (lower wins).
        public var folderPriority: Int
        /// Bigger is better (bit depth × sample rate).
        public var quality: Double

        public init(id: Int64, artist: String, title: String, album: String, duration: Double,
                    folderPriority: Int, quality: Double) {
            self.id = id
            self.artist = artist
            self.title = title
            self.album = album
            self.duration = duration
            self.folderPriority = folderPriority
            self.quality = quality
        }
    }

    /// Letters and digits only, lowercased and without accents, so "Sweet Child O' Mine" and
    /// "Sweet Child o’ Mine" (straight vs curly apostrophe) match.
    public static func fingerprint(_ text: String) -> String {
        let folded = LibraryKeys.normalize(text)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The longest gap allowed between the lengths of two copies.
    public static let durationTolerance: Double = 2

    /// For every song that's a second copy: the id of the copy that's shown instead.
    public static func duplicates(in songs: [Song]) -> [Int64: Int64] {
        var groups: [String: [Song]] = [:]
        for song in songs {
            let title = fingerprint(song.title)
            guard !title.isEmpty else { continue } // untagged files can't be told apart
            let key = [fingerprint(song.artist), title, fingerprint(song.album)].joined(separator: "\u{1F}")
            groups[key, default: []].append(song)
        }
        var result: [Int64: Int64] = [:]
        for group in groups.values where group.count > 1 {
            // Songs whose lengths chain together within the tolerance count as one song.
            let sorted = group.sorted { $0.duration < $1.duration }
            var cluster: [Song] = [sorted[0]]
            func close(_ cluster: [Song]) {
                guard cluster.count > 1 else { return }
                let best = cluster.min { a, b in
                    (a.folderPriority, -a.quality, a.id) < (b.folderPriority, -b.quality, b.id)
                }!
                for song in cluster where song.id != best.id { result[song.id] = best.id }
            }
            for song in sorted.dropFirst() {
                if song.duration - cluster.last!.duration <= durationTolerance {
                    cluster.append(song)
                } else {
                    close(cluster)
                    cluster = [song]
                }
            }
            close(cluster)
        }
        return result
    }
}
