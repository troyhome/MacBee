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

        return migrator
    }
}
