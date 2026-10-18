import Foundation
import GRDB

/// Read queries used by the UI (Home stats, Artists, Albums, search, history).
public extension LibraryDatabase {

    /// `visible()` as a GRDB filter.
    internal static var isVisible: SQLExpression {
        Column("isMissing") == false && Column("isPaused") == false && Column("isExcluded") == false
            && Column("duplicateOf") == nil
    }

    /// Columns that build an `AlbumSummary` from `track` rows grouped by albumKey.
    internal static let albumSummaryColumns = """
        albumKey,
        MAX(displayAlbum) AS title,
        MAX(displayAlbumArtist) AS artist,
        MAX(artistKey) AS artistKey,
        MAX(year) AS year,
        COUNT(*) AS trackCount,
        COALESCE(SUM(duration), 0) AS duration,
        MAX(artworkId) AS artworkId,
        MAX(sampleRate) AS maxSampleRate,
        MAX(bitDepth) AS maxBitDepth,
        MIN(dateAdded) AS dateAdded,
        MAX(lastPlayedAt) AS lastPlayedAt,
        SUM(playCount) AS playCount
        """

    func stats() async throws -> LibraryStats {
        try await writer.read { db in
            try LibraryStats.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT artistKey) AS artists,
                       COUNT(DISTINCT albumKey) AS albums,
                       COUNT(*) AS tracks,
                       COALESCE(SUM(duration), 0) AS totalDuration
                FROM track WHERE \(Self.visible())
                """) ?? .empty
        }
    }

    func albums(sortedBy sort: AlbumSort = .artist, artistKey: String? = nil, limit: Int? = nil) async throws -> [AlbumSummary] {
        let order: String
        var having = ""
        switch sort {
        case .artist: order = "artistKey, year, title COLLATE NOCASE"
        case .title: order = "title COLLATE NOCASE"
        case .year: order = "year DESC, artistKey"
        case .recentlyAdded: order = "dateAdded DESC"
        case .recentlyPlayed:
            order = "lastPlayedAt DESC"
            having = "HAVING MAX(lastPlayedAt) IS NOT NULL"
        }
        var arguments: StatementArguments = []
        var whereClause = "WHERE \(Self.visible())"
        if let artistKey {
            whereClause += " AND artistKey = ?"
            arguments += [artistKey]
        }
        var limitClause = ""
        if let limit {
            limitClause = "LIMIT ?"
            arguments += [limit]
        }
        let sql = """
            SELECT \(Self.albumSummaryColumns)
            FROM track \(whereClause)
            GROUP BY albumKey \(having)
            ORDER BY \(order) \(limitClause)
            """
        let args = arguments
        return try await writer.read { db in
            try AlbumSummary.fetchAll(db, sql: sql, arguments: args)
        }
    }

    /// One album by its key (e.g. to open the album of the song that's playing).
    func album(key albumKey: String) async throws -> AlbumSummary? {
        try await writer.read { db in
            try AlbumSummary.fetchOne(db, sql: """
                SELECT \(Self.albumSummaryColumns)
                FROM track WHERE \(Self.visible()) AND albumKey = ?
                GROUP BY albumKey
                """, arguments: [albumKey])
        }
    }

    /// Every album artist. `hidingCompilationOnly` leaves out artists whose songs are all on compilations
    /// (they have no album of their own). See `refreshVisibility` for how compilations are recognised.
    func artists(hidingCompilationOnly: Bool = false) async throws -> [ArtistSummary] {
        let having = hidingCompilationOnly ? "HAVING MIN(onCompilation) = 0" : ""
        return try await writer.read { db in
            try ArtistSummary.fetchAll(db, sql: """
                SELECT artistKey,
                       MAX(displayAlbumArtist) AS name,
                       COUNT(DISTINCT albumKey) AS albumCount,
                       COUNT(*) AS trackCount,
                       MAX(artworkId) AS artworkId
                FROM track WHERE \(Self.visible())
                GROUP BY artistKey \(having)
                ORDER BY artistKey
                """)
        }
    }

    func tracks(inAlbum albumKey: String) async throws -> [Track] {
        if albumKey.hasPrefix(Self.compilationPrefix) { return try await compilationTracks(albumKey: albumKey) }
        return try await writer.read { db in
            try Track
                .filter(Column("albumKey") == albumKey && Self.isVisible)
                .order(Column("discNumber"), Column("trackNumber"), Column("path"))
                .fetchAll(db)
        }
    }

    func track(id: Int64) async throws -> Track? {
        try await writer.read { db in try Track.fetchOne(db, key: id) }
    }

    /// Matches title, artist or album. Case- and accent-insensitive for plain ASCII; good enough for 10k+ tracks.
    func search(_ text: String, limit: Int = 200) async throws -> [Track] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        return try await writer.read { db in
            try Track.fetchAll(db, sql: """
                SELECT * FROM track
                WHERE \(Self.visible()) AND (
                    title LIKE ?1 ESCAPE '\\' OR artist LIKE ?1 ESCAPE '\\' OR
                    displayAlbum LIKE ?1 ESCAPE '\\' OR displayAlbumArtist LIKE ?1 ESCAPE '\\')
                ORDER BY artistKey, albumKey, discNumber, trackNumber
                LIMIT ?2
                """, arguments: [pattern, limit])
        }
    }

    func recentlyPlayedTracks(limit: Int = 50) async throws -> [Track] {
        try await writer.read { db in
            try Track
                .filter(Column("lastPlayedAt") != nil && Self.isVisible)
                .order(Column("lastPlayedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Missing files

    /// Tracks whose files weren't found on the last scan of a reachable folder.
    func missingTracks(limit: Int = 500) async throws -> [Track] {
        try await writer.read { db in
            try Track.filter(Column("isMissing") == true).order(Column("path")).limit(limit).fetchAll(db)
        }
    }

    func missingTrackCount() async throws -> Int {
        try await writer.read { db in try Track.filter(Column("isMissing") == true).fetchCount(db) }
    }

    /// Deletes missing tracks for good, with their play history. Returns how many were removed.
    func removeMissingTracks() async throws -> Int {
        try await writer.write { db in try Track.filter(Column("isMissing") == true).deleteAll(db) }
    }

    // MARK: - Writes from playback

    /// Call when a track has been listened to (the app decides the threshold, e.g. 50% or 4 minutes).
    func recordPlay(trackId: Int64, at date: Date = Date()) async throws {
        try await writer.write { db in
            try db.execute(sql: "INSERT INTO play (trackId, playedAt) VALUES (?, ?)", arguments: [trackId, date])
            try db.execute(sql: "UPDATE track SET playCount = playCount + 1, lastPlayedAt = ? WHERE id = ?",
                           arguments: [date, trackId])
        }
    }

    func setFavorite(trackId: Int64, _ isFavorite: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE track SET isFavorite = ? WHERE id = ?", arguments: [isFavorite, trackId])
        }
    }

    // MARK: - Folders

    func folders() async throws -> [MusicFolder] {
        try await writer.read { db in try MusicFolder.order(Column("priority"), Column("path")).fetchAll(db) }
    }

    func insertFolder(path: String, name: String) async throws -> MusicFolder {
        try await writer.write { db in
            // New folders go to the bottom of the priority list.
            let next = (try Int.fetchOne(db, sql: "SELECT MAX(priority) + 1 FROM folder")) ?? 0
            var folder = MusicFolder(id: nil, path: path, name: name, addedAt: Date(), lastScanAt: nil, priority: next)
            try folder.insert(db)
            return folder
        }
    }

    /// Removes the folder and all its tracks (and their play history).
    func deleteFolder(id: Int64) async throws {
        _ = try await writer.write { db in try MusicFolder.deleteOne(db, key: id) }
    }

    func artworkRef(id: Int64) async throws -> ArtworkRef? {
        try await writer.read { db in
            try ArtworkRecord.fetchOne(db, key: id).map { ArtworkRef(hash: $0.hash, fileExtension: $0.fileExtension) }
        }
    }
}
