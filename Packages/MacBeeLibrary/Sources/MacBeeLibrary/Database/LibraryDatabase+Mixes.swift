import Foundation
import GRDB

/// A suggested mix kept with "Save to Saved Mixes" (Collections > Saved Mixes).
public struct SavedMix: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var title: String
    public var subtitle: String
    public var createdAt: Date
    public var tracks: [Track]

    /// As a `Mix`, so the same cards can show it.
    public var mix: Mix { Mix(kind: .artist("saved:\(id)"), title: title, subtitle: subtitle, tracks: tracks) }
}

/// Built-in smart playlists (roadmap Phase 3). They fill themselves from the library every time they're opened.
/// Listed in this order. `topRated` is shown as "Favorites" (Troy); its raw value stays 3 so saved choices keep working.
public enum SmartPlaylist: Int, CaseIterable, Identifiable, Sendable {
    case topRated = 3, recentlyAdded = 1, mostPlayed = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .mostPlayed: "Most Played"
        case .topRated: "Favorites"
        }
    }

    public var subtitle: String {
        switch self {
        case .recentlyAdded: "The last \(limit) songs added"
        case .mostPlayed: "Your \(limit) most played songs"
        case .topRated: "All the songs you've hearted"
        }
    }

    public var systemImage: String {
        switch self {
        case .recentlyAdded: "clock.arrow.circlepath"
        case .mostPlayed: "flame"
        case .topRated: "heart.fill"
        }
    }

    public var limit: Int {
        switch self {
        case .recentlyAdded: 50
        case .mostPlayed: 100
        case .topRated: 1_000_000
        }
    }

    /// Smart playlists use negative ids where a playlist id is expected (the sidebar, Playlist Studio).
    public var playlistId: Int64 { -Int64(rawValue) }

    public init?(playlistId: Int64?) {
        guard let id = playlistId, id < 0 else { return nil }
        self.init(rawValue: Int(-id))
    }
}

public extension LibraryDatabase {

    // MARK: - Saved mixes

    func saveMix(title: String, subtitle: String, trackIds: [Int64], now: Date = Date()) async throws {
        try await writer.write { db in
            try db.execute(sql: "INSERT INTO savedMix (title, subtitle, createdAt) VALUES (?, ?, ?)",
                           arguments: [title, subtitle, now])
            let mixId = db.lastInsertedRowID
            for (position, trackId) in trackIds.enumerated() {
                try db.execute(sql: "INSERT INTO savedMixItem (savedMixId, trackId, position) VALUES (?, ?, ?)",
                               arguments: [mixId, trackId, position])
            }
        }
    }

    /// Saved mixes, newest first, with their songs (songs no longer in the library are left out).
    func savedMixes() async throws -> [SavedMix] {
        try await writer.read { db in
            let mixes = try Row.fetchAll(db, sql: "SELECT * FROM savedMix ORDER BY createdAt DESC, id DESC")
            return try mixes.map { row in
                let id: Int64 = row["id"]
                let tracks = try Track.fetchAll(db, sql: """
                    SELECT track.* FROM savedMixItem JOIN track ON track.id = savedMixItem.trackId
                    WHERE savedMixItem.savedMixId = ? AND \(Self.playable("track."))
                    ORDER BY savedMixItem.position
                    """, arguments: [id])
                return SavedMix(id: id, title: row["title"], subtitle: row["subtitle"], createdAt: row["createdAt"], tracks: tracks)
            }
        }
    }

    func deleteSavedMix(id: Int64) async throws {
        try await writer.write { db in try db.execute(sql: "DELETE FROM savedMix WHERE id = ?", arguments: [id]) }
    }

    // MARK: - Smart playlists

    func tracks(for smart: SmartPlaylist) async throws -> [Track] {
        let order: String
        var condition = ""
        switch smart {
        case .recentlyAdded: order = "dateAdded DESC, id DESC"
        case .mostPlayed:
            order = "playCount DESC, lastPlayedAt DESC"
            condition = "AND playCount > 0"
        case .topRated:
            // Most recently hearted first (songs hearted before this was recorded: by when they were added).
            order = "COALESCE(favoritedAt, dateAdded) DESC, id DESC"
            condition = "AND isFavorite = 1"
        }
        let sql = "SELECT * FROM track WHERE \(Self.visible()) \(condition) ORDER BY \(order) LIMIT ?"
        return try await writer.read { db in try Track.fetchAll(db, sql: sql, arguments: [smart.limit]) }
    }

    /// When each hearted song was hearted (songs hearted before MacBee recorded it fall back to when they
    /// were added), keyed by song id.
    func favoritedDates() async throws -> [Int64: Date] {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, COALESCE(favoritedAt, dateAdded) AS at FROM track WHERE isFavorite = 1")
            return Dictionary(rows.map { ($0["id"] as Int64, $0["at"] as Date) }, uniquingKeysWith: { a, _ in a })
        }
    }

    // MARK: - MiniDisc playlists

    func setPlaylistCapacity(id: Int64, seconds: Int?) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE playlist SET capacitySeconds = ? WHERE id = ?", arguments: [seconds, id])
        }
    }
}
