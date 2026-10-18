import Foundation
import GRDB

/// Roadmap Phase 2: folder priority, paused folders, duplicates and failover copies.
public extension LibraryDatabase {

    /// Saves the folder order (first = highest priority).
    func setFolderOrder(_ ids: [Int64]) async throws {
        try await writer.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE folder SET priority = ? WHERE id = ?", arguments: [index, id])
            }
        }
    }

    func setFolderPaused(id: Int64, _ paused: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE folder SET isPaused = ? WHERE id = ?", arguments: [paused, id])
        }
    }

    /// Re-works out which songs show: songs in paused folders are left out, and of each set of duplicates
    /// only the best copy shows. Returns how many songs are hidden as duplicates.
    @discardableResult
    func refreshVisibility() async throws -> Int {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE track SET isPaused = (folderId IN (SELECT id FROM folder WHERE isPaused = 1))
                """)
            let rows = try Row.fetchAll(db, sql: """
                SELECT track.id, track.artist, track.displayAlbumArtist, track.title, track.displayAlbum,
                       track.duration, track.bitDepth, track.sampleRate, folder.priority
                FROM track JOIN folder ON folder.id = track.folderId
                WHERE track.isMissing = 0 AND track.isPaused = 0
                """)
            let songs = rows.map { row in
                DuplicateFinder.Song(
                    id: row["id"],
                    artist: row["artist"] ?? row["displayAlbumArtist"] ?? "",
                    title: row["title"] ?? "",
                    album: row["displayAlbum"] ?? "",
                    duration: row["duration"] ?? 0,
                    folderPriority: row["priority"] ?? 0,
                    quality: Double((row["bitDepth"] as Int?) ?? 16) * ((row["sampleRate"] as Double?) ?? 44_100))
            }
            let duplicates = DuplicateFinder.duplicates(in: songs)
            try db.execute(sql: "UPDATE track SET duplicateOf = NULL WHERE duplicateOf IS NOT NULL")
            for (copy, shown) in duplicates {
                try db.execute(sql: "UPDATE track SET duplicateOf = ? WHERE id = ?", arguments: [shown, copy])
            }
            return duplicates.count
        }
    }

    /// Other copies of a song (its duplicates in other folders), best folder first, for when its own file
    /// can't be reached. Paused folders are skipped.
    func alternativeFiles(forTrackId id: Int64) async throws -> [String] {
        try await writer.read { db in
            let shownId = try Int64.fetchOne(db, sql: "SELECT COALESCE(duplicateOf, id) FROM track WHERE id = ?",
                                             arguments: [id]) ?? id
            return try String.fetchAll(db, sql: """
                SELECT track.path FROM track JOIN folder ON folder.id = track.folderId
                WHERE (track.id = ? OR track.duplicateOf = ?) AND track.id != ?
                  AND track.isMissing = 0 AND folder.isPaused = 0
                ORDER BY folder.priority, track.id
                """, arguments: [shownId, shownId, id])
        }
    }
}
