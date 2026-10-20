import Foundation

/// Filters for Playlist Studio's library browser.
public struct TrackFilter: Sendable, Hashable {
    public enum FormatFilter: String, Sendable, CaseIterable, Identifiable {
        case any, lossless, hiRes, flac, alac, mp3, aac, dsd
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .any: "Any format"
            case .lossless: "Lossless"
            case .hiRes: "Hi-Res (24-bit, 88.2 kHz+)"
            case .flac: "FLAC"
            case .alac: "ALAC"
            case .mp3: "MP3"
            case .aac: "AAC"
            case .dsd: "DSD"
            }
        }
    }

    public enum PlayCountFilter: String, Sendable, CaseIterable, Identifiable {
        case any, never, atLeastOnce, atLeast5, atLeast10
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .any: "Any play count"
            case .never: "Never played"
            case .atLeastOnce: "Played at least once"
            case .atLeast5: "Played 5+ times"
            case .atLeast10: "Played 10+ times"
            }
        }
    }

    /// Which fields the search text looks in. Empty means all of them.
    public enum SearchField: String, Sendable, CaseIterable, Identifiable, Hashable {
        case artist, album, title
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .artist: "Artist"
            case .album: "Album"
            case .title: "Song title"
            }
        }
    }

    public var text = ""
    public var searchFields: Set<SearchField> = []
    /// Only songs in this playlist, in playlist order. Nil means the whole library.
    public var playlistId: Int64?
    /// Exact genre, ignoring case. Nil means any.
    public var genre: String?
    public var yearFrom: Int?
    public var yearTo: Int?
    public var format: FormatFilter = .any
    /// Minimum stars, 1–5. Ratings stored as 0–100 are converted.
    public var minimumStars: Int?
    public var playCount: PlayCountFilter = .any
    public var favoritesOnly = false
    /// Only songs with no cover at all (none in the file and none in its folder).
    public var missingArtwork = false

    public init() {}
}
