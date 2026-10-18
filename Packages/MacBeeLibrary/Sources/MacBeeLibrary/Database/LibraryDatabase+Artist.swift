import Foundation
import GRDB

/// The artist page's TIDAL-style sections: similar artists and mixes built from the library.
public extension LibraryDatabase {

    /// Other artists in the library who share the most genres with this one (by how many songs of each genre
    /// they have). Compilations and Various Artists are left out.
    func similarArtists(to artistKey: String, limit: Int = 12) async throws -> [ArtistSummary] {
        let variousKey = LibraryKeys.normalize(LibraryKeys.variousArtists)
        let rows: [(key: String, genre: String?, songs: Int)] = try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT artistKey, genre, COUNT(*) AS songs FROM track
                WHERE \(Self.visible()) AND onCompilation = 0 AND genre IS NOT NULL AND TRIM(genre) != ''
                GROUP BY artistKey, genre
                """).map { ($0["artistKey"], $0["genre"], $0["songs"]) }
        }
        var weights: [String: [String: Double]] = [:]
        for row in rows {
            for genre in Self.splitGenres(row.genre) { weights[row.key, default: [:]][genre, default: 0] += Double(row.songs) }
        }
        guard let mine = weights[artistKey] else { return [] }
        let myTotal = mine.values.reduce(0, +)
        var scores: [(String, Double)] = []
        for (key, theirs) in weights where key != artistKey && key != variousKey {
            let theirTotal = theirs.values.reduce(0, +)
            let score = mine.reduce(0.0) { sum, item in
                sum + min(item.value / myTotal, (theirs[item.key] ?? 0) / theirTotal)
            }
            if score > 0 { scores.append((key, score)) }
        }
        let top = scores.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
        let all = try await artists()
        return top.compactMap { key in all.first { $0.artistKey == key } }
    }

    /// Mixes for an artist's page: a radio mix (their songs with similar artists'), their most played songs,
    /// songs not played yet, and their favorites. Mixes with too few songs are left out.
    func artistMixes(for artist: ArtistSummary) async throws -> [Mix] {
        let key = artist.artistKey
        let theirs = try await writer.read { db in
            try Track.fetchAll(db, sql: "SELECT * FROM track WHERE \(Self.visible()) AND artistKey = ?", arguments: [key])
        }
        guard !theirs.isEmpty else { return [] }
        var mixes: [Mix] = []

        let similar = try await similarArtists(to: key, limit: 5).map(\.artistKey)
        var radio = Array(theirs.shuffled().prefix(25))
        if !similar.isEmpty {
            let marks = similar.map { _ in "?" }.joined(separator: ",")
            let others = try await writer.read { db in
                try Track.fetchAll(db, sql: """
                    SELECT * FROM track WHERE \(Self.visible()) AND artistKey IN (\(marks))
                    ORDER BY RANDOM() LIMIT 25
                    """, arguments: StatementArguments(similar))
            }
            radio = (radio + others).shuffled()
        }
        mixes.append(Mix(kind: .artist("radio:\(key)"), title: "\(artist.name) Radio",
                         subtitle: similar.isEmpty ? "Shuffled" : "With similar artists", tracks: radio))

        let mostPlayed = theirs.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }.prefix(25)
        if mostPlayed.count >= 5 {
            mixes.append(Mix(kind: .artist("top:\(key)"), title: "Top Tracks", subtitle: "Most played", tracks: Array(mostPlayed)))
        }
        let unplayed = theirs.filter { $0.playCount == 0 }.shuffled().prefix(25)
        if unplayed.count >= 5 {
            mixes.append(Mix(kind: .artist("deep:\(key)"), title: "Deep Cuts", subtitle: "Not played yet", tracks: Array(unplayed)))
        }
        let favorites = theirs.filter(\.isFavorite)
        if favorites.count >= 3 {
            mixes.append(Mix(kind: .artist("fav:\(key)"), title: "Favorites", subtitle: "Songs you've hearted", tracks: favorites))
        }
        return mixes
    }

    /// "Rock; Indie Rock" -> ["rock", "indie rock"]
    internal static func splitGenres(_ raw: String?) -> [String] {
        (raw ?? "").split(whereSeparator: { ";,/".contains($0) })
            .map { LibraryKeys.normalize(String($0)) }
            .filter { !$0.isEmpty }
    }
}
