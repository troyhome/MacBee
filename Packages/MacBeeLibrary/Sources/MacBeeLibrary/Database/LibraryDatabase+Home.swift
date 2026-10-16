import Foundation
import GRDB

/// Queries for the Home screen: play history, forgotten gems and suggested mixes.
public extension LibraryDatabase {

    // MARK: - Play history

    /// Plays, newest first. Pass the oldest `playedAt` you have as `before` to load the next page.
    func playHistory(limit: Int = 100, before: Date? = nil) async throws -> [PlayHistoryEntry] {
        try await writer.read { db in
            var sql = """
                SELECT play.id AS playId, play.playedAt AS playedAt, track.*
                FROM play JOIN track ON track.id = play.trackId
                WHERE track.isMissing = 0
                """
            var arguments: StatementArguments = []
            if let before {
                sql += " AND play.playedAt < ?"
                arguments += [before]
            }
            sql += " ORDER BY play.playedAt DESC, play.id DESC LIMIT ?"
            arguments += [limit]
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                PlayHistoryEntry(playId: row["playId"], playedAt: row["playedAt"], track: try Track(row: row))
            }
        }
    }

    // MARK: - Forgotten gems

    /// Albums you used to play (3+ plays) but haven't in 6 months, and albums with favorites
    /// you haven't played in 3 months. Most-played first.
    func forgottenGems(now: Date = Date(), limit: Int = 20) async throws -> [AlbumSummary] {
        let calendar = Calendar.current
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
        return try await writer.read { db in
            try AlbumSummary.fetchAll(db, sql: """
                SELECT \(Self.albumSummaryColumns)
                FROM track WHERE isMissing = 0
                GROUP BY albumKey
                HAVING (SUM(playCount) >= 3 AND MAX(lastPlayedAt) < ?)
                    OR (MAX(isFavorite) = 1 AND (MAX(lastPlayedAt) IS NULL OR MAX(lastPlayedAt) < ?))
                ORDER BY SUM(playCount) DESC, MAX(lastPlayedAt)
                LIMIT ?
                """, arguments: [sixMonthsAgo, threeMonthsAgo, limit])
        }
    }

    // MARK: - Suggested mixes

    /// Builds up to six mixes: Most Played, top genres, top decade, Hi-Res Picks, Favorites.
    /// Mixes with too few tracks are left out. `day` keeps each mix's order stable for a day.
    func suggestedMixes(day: Int = LibraryDatabase.dayNumber(), tracksPerMix: Int = 100) async throws -> [Mix] {
        try await writer.read { db in
            var mixes: [Mix] = []
            func add(_ kind: Mix.Kind, _ title: String, _ subtitle: String, minimum: Int) throws {
                let tracks = try Self.tracks(for: kind, day: day, limit: tracksPerMix, db: db)
                if tracks.count >= minimum { mixes.append(Mix(kind: kind, title: title, subtitle: subtitle, tracks: tracks)) }
            }

            try add(.mostPlayed, "Most Played", "Your favourites, by play count", minimum: 5)
            let genres = try String.fetchAll(db, sql: """
                SELECT MAX(genre) FROM track
                WHERE isMissing = 0 AND genre IS NOT NULL AND TRIM(genre) != ''
                GROUP BY genre COLLATE NOCASE
                HAVING COUNT(*) >= 20
                ORDER BY COUNT(*) DESC LIMIT 2
                """)
            for genre in genres {
                let name = genre.prefix(1).uppercased() + genre.dropFirst() // "rock" -> "Rock"
                try add(.genre(genre), "\(name) Mix", "From your \(name) albums", minimum: 10)
            }
            if let decade = try Int.fetchOne(db, sql: """
                SELECT (year / 10) * 10 AS decade FROM track
                WHERE isMissing = 0 AND year >= 1900
                GROUP BY decade HAVING COUNT(*) >= 20
                ORDER BY COUNT(*) DESC LIMIT 1
                """) {
                try add(.decade(decade), "\(decade)s", "The decade you play the most", minimum: 10)
            }
            try add(.hiRes, "Hi-Res Picks", "24-bit, 88.2 kHz and up", minimum: 10)
            try add(.favorites, "Favorites", "Songs you've hearted", minimum: 5)
            return Array(mixes.prefix(6))
        }
    }

    /// Days since 1970, used to reshuffle mixes once a day.
    static func dayNumber(for date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970 / 86_400)
    }

    internal static func tracks(for kind: Mix.Kind, day: Int, limit: Int, db: Database) throws -> [Track] {
        // Same order all day, different tomorrow: a cheap pseudo-random shuffle seeded by the day.
        // Multiplicative hashing: an odd multiplier that changes each day scrambles the track ids.
        let seed = UInt64(truncatingIfNeeded: day) &* 0x9E37_79B9_7F4A_7C15
        let multiplier = (seed >> 32) | 1                 // odd, below 2^32, very different each day
        let offset = seed & 0xFFFF_FFFF
        let dailyOrder = "((id * \(multiplier)) + \(offset)) % 4294967296"
        let base = "SELECT * FROM track WHERE isMissing = 0"
        switch kind {
        case .mostPlayed:
            return try Track.fetchAll(db, sql: "\(base) AND playCount > 0 ORDER BY playCount DESC, lastPlayedAt DESC LIMIT ?",
                                      arguments: [limit])
        case let .genre(genre):
            return try Track.fetchAll(db, sql: "\(base) AND genre = ? COLLATE NOCASE ORDER BY \(dailyOrder) LIMIT ?",
                                      arguments: [genre, limit])
        case let .decade(start):
            return try Track.fetchAll(db, sql: "\(base) AND year BETWEEN ? AND ? ORDER BY \(dailyOrder) LIMIT ?",
                                      arguments: [start, start + 9, limit])
        case .hiRes:
            return try Track.fetchAll(db, sql: """
                \(base) AND ((bitDepth >= 24 AND sampleRate >= 88200) OR codec = 'DSD')
                ORDER BY \(dailyOrder) LIMIT ?
                """, arguments: [limit])
        case .favorites:
            return try Track.fetchAll(db, sql: "\(base) AND isFavorite = 1 ORDER BY \(dailyOrder) LIMIT ?",
                                      arguments: [limit])
        }
    }
}
