import Foundation
import GRDB

/// Queries for the Collection page: the songs and albums you've marked as favorites.
public extension LibraryDatabase {

    /// Favorite songs, by artist, album and track order.
    func favoriteTracks() async throws -> [Track] {
        try await writer.read { db in
            try Track.fetchAll(db, sql: """
                SELECT * FROM track
                WHERE \(Self.visible()) AND isFavorite = 1
                ORDER BY artistKey, albumKey, discNumber, trackNumber, path
                """)
        }
    }

    /// Albums whose every (present) song is a favorite. The album page's heart button favorites all its songs.
    func favoriteAlbums() async throws -> [AlbumSummary] {
        try await writer.read { db in
            try AlbumSummary.fetchAll(db, sql: """
                SELECT \(Self.albumSummaryColumns)
                FROM track WHERE \(Self.visible())
                GROUP BY albumKey
                HAVING MIN(isFavorite) = 1
                ORDER BY artistKey, year, title COLLATE NOCASE
                """)
        }
    }

    /// Compilation albums, all under Various Artists: albums tagged as compilations or filed under Various
    /// Artists, plus untagged ones (songs by several artists in one folder), grouped by album title.
    /// Their `albumKey` starts with `compilationPrefix`; `tracks(inAlbum:)` understands it.
    func compilationAlbums() async throws -> [AlbumSummary] {
        try await writer.read { db in
            try AlbumSummary.fetchAll(db, sql: """
                SELECT '\(Self.compilationPrefix)' || LOWER(displayAlbum) AS albumKey,
                       MAX(displayAlbum) AS title,
                       ? AS artist,
                       ? AS artistKey,
                       MAX(year) AS year,
                       COUNT(*) AS trackCount,
                       COALESCE(SUM(duration), 0) AS duration,
                       MAX(artworkId) AS artworkId,
                       MAX(sampleRate) AS maxSampleRate,
                       MAX(bitDepth) AS maxBitDepth,
                       MIN(dateAdded) AS dateAdded,
                       MAX(lastPlayedAt) AS lastPlayedAt,
                       SUM(playCount) AS playCount
                FROM track WHERE \(Self.visible()) AND onCompilation = 1
                GROUP BY LOWER(displayAlbum)
                ORDER BY title COLLATE NOCASE
                """, arguments: [LibraryKeys.variousArtists, LibraryKeys.normalize(LibraryKeys.variousArtists)])
        }
    }

    /// Start of the album key for a compilation album from `compilationAlbums()`.
    static let compilationPrefix = "compilation:"

    /// The songs of a compilation album from `compilationAlbums()`.
    internal func compilationTracks(albumKey: String) async throws -> [Track] {
        let title = String(albumKey.dropFirst(Self.compilationPrefix.count))
        return try await writer.read { db in
            try Track.fetchAll(db, sql: """
                SELECT * FROM track
                WHERE \(Self.visible()) AND onCompilation = 1 AND LOWER(displayAlbum) = ?
                ORDER BY discNumber, trackNumber, path
                """, arguments: [title])
        }
    }
}
