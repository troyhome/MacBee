import Foundation
import GRDB

/// The library's SQLite database. Safe to use from any thread.
///
/// Uses a DatabasePool (WAL mode), so the UI can read while a scan is writing.
public final class LibraryDatabase: Sendable {
    let writer: any DatabaseWriter

    /// Opens (or creates) the database file.
    public init(fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        writer = try DatabasePool(path: fileURL.path)
        try Self.migrator.migrate(writer)
    }

    /// In-memory database, for tests and previews.
    public init() throws {
        writer = try DatabaseQueue()
        try Self.migrator.migrate(writer)
    }

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "folder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("addedAt", .datetime).notNull()
                t.column("lastScanAt", .datetime)
            }

            try db.create(table: "artwork") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("hash", .text).notNull().unique()
                t.column("fileExtension", .text).notNull()
            }

            try db.create(table: "track") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("folderId", .integer).notNull().indexed()
                    .references("folder", onDelete: .cascade)
                t.column("path", .text).notNull().unique()
                t.column("fileSize", .integer).notNull()
                t.column("modifiedAt", .datetime).notNull()

                t.column("title", .text)
                t.column("artist", .text)
                t.column("albumArtist", .text)
                t.column("album", .text)
                t.column("genre", .text)
                t.column("composer", .text)
                t.column("year", .integer)
                t.column("trackNumber", .integer)
                t.column("trackTotal", .integer)
                t.column("discNumber", .integer)
                t.column("discTotal", .integer)
                t.column("isCompilation", .boolean).notNull().defaults(to: false)

                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("sampleRate", .double)
                t.column("bitDepth", .integer)
                t.column("channels", .integer)
                t.column("bitrate", .double)
                t.column("codec", .text).notNull()

                t.column("displayAlbum", .text).notNull()
                t.column("displayAlbumArtist", .text).notNull()
                t.column("albumKey", .text).notNull().indexed()
                t.column("artistKey", .text).notNull().indexed()
                t.column("artworkId", .integer).references("artwork", onDelete: .setNull)

                t.column("dateAdded", .datetime).notNull().indexed()
                t.column("playCount", .integer).notNull().defaults(to: 0)
                t.column("lastPlayedAt", .datetime).indexed()
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("rating", .integer)
                t.column("isMissing", .boolean).notNull().defaults(to: false).indexed()
            }

            // Play history (used by Recently Played, Forgotten Gems, mixes in later phases).
            try db.create(table: "play") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("trackId", .integer).notNull().indexed()
                    .references("track", onDelete: .cascade)
                t.column("playedAt", .datetime).notNull().indexed()
            }
        }

        // Phase 7: playlists and playlist folders.
        migrator.registerMigration("v2") { db in
            try db.create(table: "playlist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("parentFolderId", .integer).indexed()
                    .references("playlist", onDelete: .cascade)
                t.column("isFolder", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "playlistItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("playlistId", .integer).notNull().indexed()
                    .references("playlist", onDelete: .cascade)
                t.column("trackId", .integer).notNull().indexed()
                    .references("track", onDelete: .cascade)
                t.column("position", .integer).notNull()
            }
        }

        // Playlist pictures chosen by the user.
        migrator.registerMigration("v3") { db in
            try db.alter(table: "playlist") { t in
                t.add(column: "artworkId", .integer).references("artwork", onDelete: .setNull)
            }
        }

        // Phase 8: where each song's file is on the Plex server (for playing away from home).
        migrator.registerMigration("v4") { db in
            try db.create(table: "plexLink") { t in
                t.primaryKey("trackId", .integer).references("track", onDelete: .cascade)
                t.column("partKey", .text).notNull()
            }
        }

        // Roadmap Phase 2: folder priority and pausing, duplicates merged into one visible song.
        migrator.registerMigration("v5") { db in
            try db.alter(table: "folder") { t in
                t.add(column: "priority", .integer).notNull().defaults(to: 0)
                t.add(column: "isPaused", .boolean).notNull().defaults(to: false)
            }
            // Existing folders keep their old order (alphabetical by path) as their priority.
            let ids = try Int64.fetchAll(db, sql: "SELECT id FROM folder ORDER BY path")
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE folder SET priority = ? WHERE id = ?", arguments: [index, id])
            }
            try db.alter(table: "track") { t in
                t.add(column: "isPaused", .boolean).notNull().defaults(to: false)
                t.add(column: "duplicateOf", .integer)
            }
            try db.create(index: "track_on_isPaused", on: "track", columns: ["isPaused"])
            try db.create(index: "track_on_duplicateOf", on: "track", columns: ["duplicateOf"])
        }

        // Duplicates page: copies removed from the library by hand; songs that sit on compilations.
        migrator.registerMigration("v6") { db in
            try db.alter(table: "track") { t in
                t.add(column: "isExcluded", .boolean).notNull().defaults(to: false)
                t.add(column: "onCompilation", .boolean).notNull().defaults(to: false)
            }
        }

        // Duplicates page: copies Troy has accepted (kept on purpose), so they stop being listed.
        migrator.registerMigration("v7") { db in
            try db.alter(table: "track") { t in
                t.add(column: "duplicateAccepted", .boolean).notNull().defaults(to: false)
            }
        }

        // Roadmap Phase 3: saved mixes, and a running-time limit for MiniDisc playlists.
        migrator.registerMigration("v8") { db in
            try db.alter(table: "playlist") { t in
                t.add(column: "capacitySeconds", .integer)
            }
            try db.create(table: "savedMix") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("subtitle", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "savedMixItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("savedMixId", .integer).notNull().indexed().references("savedMix", onDelete: .cascade)
                t.column("trackId", .integer).notNull().indexed().references("track", onDelete: .cascade)
                t.column("position", .integer).notNull()
            }
        }

        // When each song was hearted, for the Favorites page's Date Added column. A trigger keeps it right
        // however a song is hearted (the heart button, an album's heart, a sync from another Mac).
        migrator.registerMigration("v9") { db in
            try db.alter(table: "track") { t in
                t.add(column: "favoritedAt", .datetime)
            }
            try db.execute(sql: """
                CREATE TRIGGER trackFavoritedAt AFTER UPDATE OF isFavorite ON track
                WHEN NEW.isFavorite IS NOT OLD.isFavorite
                BEGIN
                    UPDATE track SET favoritedAt = CASE WHEN NEW.isFavorite THEN strftime('%Y-%m-%d %H:%M:%f', 'now') END
                    WHERE id = NEW.id;
                END
                """)
        }

        return migrator
    }

    /// SQL for songs that show in the library: present, not in a paused folder, and not a second copy of a
    /// song (duplicates show once, as their best copy). `prefix` is a table name with a dot, e.g. "track.".
    static func visible(_ prefix: String = "") -> String {
        "\(prefix)isMissing = 0 AND \(prefix)isPaused = 0 AND \(prefix)isExcluded = 0 AND \(prefix)duplicateOf IS NULL"
    }

    /// SQL for songs a playlist shows: like `visible`, but a duplicate copy someone put in a playlist stays.
    /// (Copies removed on the Duplicates page leave playlists too.)
    static func playable(_ prefix: String = "") -> String {
        "\(prefix)isMissing = 0 AND \(prefix)isPaused = 0 AND \(prefix)isExcluded = 0"
    }
}
