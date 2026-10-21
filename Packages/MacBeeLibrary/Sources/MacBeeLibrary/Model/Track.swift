import Foundation
import GRDB

/// One audio file in the library. Stored in the `track` table.
public struct Track: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var folderId: Int64
    public var path: String
    public var fileSize: Int64
    public var modifiedAt: Date

    // Tags (as written in the file; nil when missing)
    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var genre: String?
    public var composer: String?
    public var year: Int?
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var isCompilation: Bool

    // Audio format
    public var duration: Double
    public var sampleRate: Double?
    public var bitDepth: Int?
    public var channels: Int?
    public var bitrate: Double?
    public var codec: String

    // Grouping (derived from tags, with fallbacks)
    public var displayAlbum: String
    public var displayAlbumArtist: String
    public var albumKey: String
    public var artistKey: String
    public var artworkId: Int64?

    // Library state
    public var dateAdded: Date
    public var playCount: Int
    public var lastPlayedAt: Date?
    public var isFavorite: Bool
    public var rating: Int?
    /// File not found on the last scan of a reachable folder. Hidden, but kept so
    /// play history and favorites survive if the file comes back or was moved.
    public var isMissing: Bool

    public static let databaseTableName = "track"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var displayTitle: String {
        title?.nonEmpty ?? url.deletingPathExtension().lastPathComponent
    }

    public var displayArtist: String {
        artist?.nonEmpty ?? albumArtist?.nonEmpty ?? LibraryKeys.unknownArtist
    }

    /// e.g. "FLAC 24/96"
    public var formatSummary: String {
        var parts = [codec]
        if let bits = bitDepth, let rate = sampleRate, bits > 1 {
            let khz = rate / 1000
            let rateText = khz.rounded() == khz ? "\(Int(khz))" : String(format: "%.1f", khz)
            parts.append("\(bits)/\(rateText)")
        }
        return parts.joined(separator: " ")
    }
}

extension Track {
    /// A new track from scan results.
    init(scanned s: ScannedTrack, folderId: Int64, artworkId: Int64?, now: Date) {
        self.init(id: nil, folderId: folderId, path: s.path, fileSize: s.fileSize, modifiedAt: s.modifiedAt,
                  title: nil, artist: nil, albumArtist: nil, album: nil, genre: nil, composer: nil, year: nil,
                  trackNumber: nil, trackTotal: nil, discNumber: nil, discTotal: nil, isCompilation: false,
                  duration: 0, sampleRate: nil, bitDepth: nil, channels: nil, bitrate: nil, codec: s.codec,
                  displayAlbum: "", displayAlbumArtist: "", albumKey: "", artistKey: "", artworkId: nil,
                  dateAdded: min(s.createdAt ?? now, now), playCount: 0, lastPlayedAt: nil,
                  isFavorite: false, rating: nil, isMissing: false)
        apply(s, folderId: folderId, artworkId: artworkId)
    }

    /// Refreshes file and tag fields from a new scan; keeps play counts, favorites and date added.
    mutating func apply(_ s: ScannedTrack, folderId: Int64, artworkId: Int64?) {
        self.folderId = folderId
        path = s.path
        fileSize = s.fileSize
        modifiedAt = s.modifiedAt
        title = s.title
        artist = s.artist
        albumArtist = s.albumArtist
        album = s.album
        genre = s.genre
        composer = s.composer
        year = s.year
        trackNumber = s.trackNumber
        trackTotal = s.trackTotal
        discNumber = s.discNumber
        discTotal = s.discTotal
        isCompilation = s.isCompilation
        duration = s.duration
        sampleRate = s.sampleRate
        bitDepth = s.bitDepth
        channels = s.channels
        bitrate = s.bitrate
        codec = s.codec
        if let tagRating = s.rating { rating = tagRating }
        self.artworkId = artworkId
        isMissing = false // just read from disk, so it's there (matters for a moved file matched to a missing song)

        displayAlbumArtist = LibraryKeys.albumArtist(albumArtist: s.albumArtist, artist: s.artist,
                                                     isCompilation: s.isCompilation)
        displayAlbum = LibraryKeys.albumTitle(album: s.album, fileURL: URL(fileURLWithPath: s.path))
        albumKey = LibraryKeys.albumKey(albumArtist: displayAlbumArtist, albumTitle: displayAlbum)
        artistKey = LibraryKeys.normalize(displayAlbumArtist)
        isMissing = false
    }
}

/// Everything read from one file during a scan, before it goes into the database.
public struct ScannedTrack: Sendable, Equatable {
    public var path: String
    public var fileSize: Int64
    public var modifiedAt: Date
    public var createdAt: Date?

    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var genre: String?
    public var composer: String?
    public var year: Int?
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var isCompilation: Bool = false
    public var rating: Int?

    public var duration: Double = 0
    public var sampleRate: Double?
    public var bitDepth: Int?
    public var channels: Int?
    public var bitrate: Double?
    public var codec: String = "PCM"

    public var artwork: ArtworkRef?

    public init(path: String, fileSize: Int64, modifiedAt: Date, createdAt: Date? = nil) {
        self.path = path
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
    }
}
