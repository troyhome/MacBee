import Foundation
import GRDB

/// Playlists, playlist folders and Playlist Studio queries.
public extension LibraryDatabase {

    // MARK: - Playlists and folders

    /// Every playlist and folder (build the sidebar tree with `PlaylistTree.build`).
    func playlists() async throws -> [Playlist] {
        try await writer.read { db in
            try Playlist.order(Column("parentFolderId"), Column("sortOrder"), Column("name")).fetchAll(db)
        }
    }

    /// Adds a playlist or folder at the end of `parentFolderId`.
    func createPlaylist(name: String, isFolder: Bool = false, parentFolderId: Int64? = nil,
                        now: Date = Date()) async throws -> Playlist {
        try await writer.write { db in
            let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM playlist WHERE parentFolderId IS ?",
                                        arguments: [parentFolderId]) ?? 0
            var playlist = Playlist(id: nil, name: name, parentFolderId: parentFolderId, isFolder: isFolder,
                                    sortOrder: next, createdAt: now, artworkId: nil)
            try playlist.insert(db)
            return playlist
        }
    }

    func renamePlaylist(id: Int64, to name: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE playlist SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    /// Sets (or with nil, removes) the playlist's own picture, already saved in the artwork cache.
    func setPlaylistArtwork(playlistId: Int64, to ref: ArtworkRef?) async throws {
        try await writer.write { db in
            let artworkId = try ref.flatMap { try Self.artworkId(for: $0, db: db) }
            try db.execute(sql: "UPDATE playlist SET artworkId = ? WHERE id = ?", arguments: [artworkId, playlistId])
        }
    }

    /// Deletes a playlist, or a folder with everything inside it. Songs stay in the library.
    func deletePlaylist(id: Int64) async throws {
        _ = try await writer.write { db in try Playlist.deleteOne(db, key: id) }
    }

    /// Moves a playlist or folder into `parentFolderId` (nil = top level) at position `index` among its new siblings.
    /// Moving a folder into itself or one of its own subfolders is ignored.
    func movePlaylist(id: Int64, toFolder parentFolderId: Int64?, at index: Int) async throws {
        try await writer.write { db in
            if let parent = parentFolderId {
                // Walk up from the destination; if we meet the moved item, it would end up inside itself.
                var cursor: Int64? = parent
                while let current = cursor {
                    if current == id { return }
                    cursor = try Int64.fetchOne(db, sql: "SELECT parentFolderId FROM playlist WHERE id = ?", arguments: [current])
                }
            }
            var siblings = try Int64.fetchAll(db, sql: """
                SELECT id FROM playlist WHERE parentFolderId IS ? AND id != ? ORDER BY sortOrder, name
                """, arguments: [parentFolderId, id])
            siblings.insert(id, at: min(max(index, 0), siblings.count))
            try db.execute(sql: "UPDATE playlist SET parentFolderId = ? WHERE id = ?", arguments: [parentFolderId, id])
            for (order, siblingId) in siblings.enumerated() {
                try db.execute(sql: "UPDATE playlist SET sortOrder = ? WHERE id = ?", arguments: [order, siblingId])
            }
        }
    }

    // MARK: - Playlist songs

    /// The playlist's songs in order. Songs whose files are missing are left out (but kept in the playlist).
    func playlistEntries(playlistId: Int64) async throws -> [PlaylistEntry] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT playlistItem.id AS itemId, track.*
                FROM playlistItem JOIN track ON track.id = playlistItem.trackId
                WHERE playlistItem.playlistId = ? AND \(Self.playable("track."))
                ORDER BY playlistItem.position, playlistItem.id
                """, arguments: [playlistId]).map { row in
                PlaylistEntry(itemId: row["itemId"], track: try Track(row: row))
            }
        }
    }

    /// Adds songs at the end of the playlist, or before position `index` of its visible songs.
    func addTracks(_ trackIds: [Int64], toPlaylist playlistId: Int64, at index: Int? = nil) async throws {
        guard !trackIds.isEmpty else { return }
        try await writer.write { db in
            var order = try Int64.fetchAll(db, sql: "SELECT id FROM playlistItem WHERE playlistId = ? ORDER BY position, id",
                                           arguments: [playlistId])
            var newIds: [Int64] = []
            for trackId in trackIds {
                var item = PlaylistItemRecord(id: nil, playlistId: playlistId, trackId: trackId, position: 0)
                try item.insert(db)
                if let id = item.id { newIds.append(id) }
            }
            order.insert(contentsOf: newIds, at: min(max(index ?? order.count, 0), order.count))
            try Self.renumber(order, db: db)
        }
    }

    func removeEntries(_ itemIds: [Int64], fromPlaylist playlistId: Int64) async throws {
        try await writer.write { db in
            try PlaylistItemRecord.filter(keys: itemIds).filter(Column("playlistId") == playlistId).deleteAll(db)
            let order = try Int64.fetchAll(db, sql: "SELECT id FROM playlistItem WHERE playlistId = ? ORDER BY position, id",
                                           arguments: [playlistId])
            try Self.renumber(order, db: db)
        }
    }

    /// Saves a new order. `itemIds` is the visible order; hidden (missing) entries keep their place at the end.
    func reorderEntries(playlistId: Int64, itemIds: [Int64]) async throws {
        try await writer.write { db in
            let all = try Int64.fetchAll(db, sql: "SELECT id FROM playlistItem WHERE playlistId = ? ORDER BY position, id",
                                         arguments: [playlistId])
            let visible = itemIds.filter(all.contains)
            let hidden = all.filter { !visible.contains($0) }
            try Self.renumber(visible + hidden, db: db)
        }
    }

    /// Song count, length and covers (for headers and cards).
    func playlistSummary(playlistId: Int64) async throws -> PlaylistSummary {
        try await writer.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS count, COALESCE(SUM(track.duration), 0) AS duration
                FROM playlistItem JOIN track ON track.id = playlistItem.trackId
                WHERE playlistItem.playlistId = ? AND \(Self.playable("track."))
                """, arguments: [playlistId])
            let artwork = try Int64.fetchAll(db, sql: """
                SELECT track.artworkId FROM playlistItem JOIN track ON track.id = playlistItem.trackId
                WHERE playlistItem.playlistId = ? AND \(Self.playable("track.")) AND track.artworkId IS NOT NULL
                GROUP BY track.artworkId ORDER BY MIN(playlistItem.position) LIMIT 4
                """, arguments: [playlistId])
            return PlaylistSummary(trackCount: row?["count"] ?? 0, duration: row?["duration"] ?? 0, artworkIds: artwork)
        }
    }

    /// Tracks with these exact file paths, in the same order (unknown paths are skipped). Used by M3U import.
    func tracks(atPaths paths: [String]) async throws -> [Track] {
        guard !paths.isEmpty else { return [] }
        return try await writer.read { db in
            let found = try Track.filter(paths.contains(Column("path"))).fetchAll(db)
            let byPath = Dictionary(found.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            return paths.compactMap { byPath[$0] }
        }
    }

    /// Tracks with these ids, in the same order (unknown ids are skipped). Used for drag and drop.
    func tracks(ids: [Int64]) async throws -> [Track] {
        guard !ids.isEmpty else { return [] }
        return try await writer.read { db in
            let found = try Track.fetchAll(db, keys: ids)
            let byId = Dictionary(found.compactMap { t in t.id.map { ($0, t) } }, uniquingKeysWith: { first, _ in first })
            return ids.compactMap { byId[$0] }
        }
    }

    // MARK: - Playlist Studio

    /// Genres in the library, most common first.
    func genres() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT MAX(genre) FROM track
                WHERE \(Self.visible()) AND genre IS NOT NULL AND TRIM(genre) != ''
                GROUP BY genre COLLATE NOCASE ORDER BY COUNT(*) DESC
                """)
        }
    }

    /// Library songs matching Playlist Studio's filters, by artist, album and track number.
    func tracks(matching filter: TrackFilter, limit: Int = 1000) async throws -> [Track] {
        var conditions = [Self.visible()]
        var arguments: StatementArguments = []
        let text = filter.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let pattern = "%" + text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
            let fields = filter.searchFields.isEmpty ? Set(TrackFilter.SearchField.allCases) : filter.searchFields
            var matches: [String] = []
            if fields.contains(.title) { matches.append("title LIKE ? ESCAPE '\\'") }
            if fields.contains(.artist) { matches += ["artist LIKE ? ESCAPE '\\'", "displayAlbumArtist LIKE ? ESCAPE '\\'"] }
            if fields.contains(.album) { matches.append("displayAlbum LIKE ? ESCAPE '\\'") }
            conditions.append("(" + matches.joined(separator: " OR ") + ")")
            arguments += StatementArguments(Array(repeating: pattern, count: matches.count))
        }
        if let genre = filter.genre {
            conditions.append("genre = ? COLLATE NOCASE")
            arguments += [genre]
        }
        if let from = filter.yearFrom {
            conditions.append("year >= ?")
            arguments += [from]
        }
        if let to = filter.yearTo {
            conditions.append("year <= ?")
            arguments += [to]
        }
        switch filter.format {
        case .any: break
        case .lossless: conditions.append("codec IN ('FLAC', 'ALAC', 'WAV', 'AIFF', 'DSD')")
        case .hiRes: conditions.append("((bitDepth >= 24 AND sampleRate >= 88200) OR codec = 'DSD')")
        case .flac: conditions.append("codec = 'FLAC'")
        case .alac: conditions.append("codec = 'ALAC'")
        case .mp3: conditions.append("codec = 'MP3'")
        case .aac: conditions.append("codec = 'AAC'")
        case .dsd: conditions.append("codec = 'DSD'")
        }
        if let stars = filter.minimumStars {
            // Tags store ratings as 0–5 stars or 0–100; convert the second kind to stars.
            conditions.append("(CASE WHEN rating <= 5 THEN rating ELSE (rating + 10) / 20 END) >= ?")
            arguments += [stars]
        }
        switch filter.playCount {
        case .any: break
        case .never: conditions.append("playCount = 0")
        case .atLeastOnce: conditions.append("playCount >= 1")
        case .atLeast5: conditions.append("playCount >= 5")
        case .atLeast10: conditions.append("playCount >= 10")
        }
        if filter.favoritesOnly { conditions.append("isFavorite = 1") }
        var order = "artistKey, year, albumKey, discNumber, trackNumber"
        if let playlistId = filter.playlistId {
            conditions.append("id IN (SELECT trackId FROM playlistItem WHERE playlistId = ?)")
            arguments += [playlistId]
            order = "(SELECT MIN(position) FROM playlistItem WHERE playlistId = \(playlistId) AND trackId = track.id)"
        }
        arguments += [limit]
        let sql = """
            SELECT * FROM track WHERE \(conditions.joined(separator: " AND "))
            ORDER BY \(order) LIMIT ?
            """
        let args = arguments
        return try await writer.read { db in try Track.fetchAll(db, sql: sql, arguments: args) }
    }

    // MARK: - Helpers

    private static func renumber(_ itemIds: [Int64], db: Database) throws {
        for (position, id) in itemIds.enumerated() {
            try db.execute(sql: "UPDATE playlistItem SET position = ? WHERE id = ?", arguments: [position, id])
        }
    }
}
