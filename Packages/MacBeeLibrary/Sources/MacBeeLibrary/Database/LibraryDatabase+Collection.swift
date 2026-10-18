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
}
