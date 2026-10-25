import Foundation
import GRDB

/// A folder MacBee watches (local or network). Stored in the `folder` table.
public struct MusicFolder: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var path: String
    public var name: String
    public var addedAt: Date
    public var lastScanAt: Date?
    /// Lower comes first: decides which copy of a duplicated song is shown and played.
    public var priority: Int = 0
    /// Paused folders stay in the list but their songs are left out of the library.
    public var isPaused: Bool = false
    /// Which drive the folder is on ("smb://server/share" or "uuid:…") and where on it, so MacBee can find it
    /// again when the drive is mounted somewhere else. Nil on the Mac's own disk. See `VolumeLocation`.
    public var volumeID: String?
    public var pathInVolume: String?

    public static let databaseTableName = "folder"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// The folder exists and can be read (network drive mounted, external drive plugged in). An empty folder left
    /// in /Volumes by a drive that went away, or another drive that took the same name, doesn't count.
    public var isReachable: Bool { VolumeLocation.isConnected(path, volumeID: volumeID) }

    public var isNetwork: Bool {
        (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false
    }
}

/// Cover image saved in the artwork cache. Stored in the `artwork` table.
struct ArtworkRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var hash: String
    var fileExtension: String

    static let databaseTableName = "artwork"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Reference to a cached cover image (content hash), produced during scanning.
public struct ArtworkRef: Sendable, Hashable {
    public var hash: String
    public var fileExtension: String
}

/// Numbers for the Home screen.
public struct LibraryStats: Decodable, Sendable, Equatable, FetchableRecord {
    public var artists: Int
    public var albums: Int
    public var tracks: Int
    public var totalDuration: Double

    public static let empty = LibraryStats(artists: 0, albums: 0, tracks: 0, totalDuration: 0)
}

public struct AlbumSummary: Decodable, Identifiable, Hashable, Sendable, FetchableRecord {
    public var albumKey: String
    public var title: String
    public var artist: String
    public var artistKey: String
    public var year: Int?
    public var trackCount: Int
    public var duration: Double
    public var artworkId: Int64?
    public var maxSampleRate: Double?
    public var maxBitDepth: Int?
    public var dateAdded: Date
    public var lastPlayedAt: Date?
    public var playCount: Int

    public var id: String { albumKey }
}

public struct ArtistSummary: Decodable, Identifiable, Hashable, Sendable, FetchableRecord {
    public var artistKey: String
    public var name: String
    public var albumCount: Int
    public var trackCount: Int
    public var artworkId: Int64?

    public var id: String { artistKey }
}

public enum AlbumSort: Sendable {
    case artist
    case title
    case year
    case recentlyAdded
    case recentlyPlayed
}

// MARK: - Scanning progress and results

public struct ScanProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case checking          // looking for new, changed and removed files
        case reading           // reading tags and artwork
        case finishing
    }
    public var folderName: String
    public var phase: Phase
    public var filesFound: Int
    public var done: Int
    public var total: Int

    public var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

public struct ScanReport: Sendable, Equatable {
    public var folderPath: String
    /// Folder couldn't be reached (drive unmounted). Nothing was changed.
    public var wasOffline = false
    /// Folder looked empty though tracks were expected; removals were skipped as a precaution.
    public var skippedRemovals = false
    public var cancelled = false
    public var added = 0
    public var updated = 0
    public var moved = 0
    public var missing = 0
    public var restored = 0
    public var unchanged = 0
    public var failedPaths: [String] = []
    public var failedCount = 0
    public var seconds: Double = 0

    public init(folderPath: String) {
        self.folderPath = folderPath
    }

    public var changedAnything: Bool {
        added + updated + moved + missing + restored > 0
    }
}

public enum LibraryError: LocalizedError {
    case folderNotFound(String)
    case folderAlreadyAdded(String)
    case folderOverlaps(String, String)

    public var errorDescription: String? {
        switch self {
        case let .folderNotFound(path): return "Folder not found: \(path)"
        case let .folderAlreadyAdded(path): return "Already in the library: \(path)"
        case let .folderOverlaps(new, existing): return "\(new) overlaps a folder already in the library (\(existing))."
        }
    }
}
