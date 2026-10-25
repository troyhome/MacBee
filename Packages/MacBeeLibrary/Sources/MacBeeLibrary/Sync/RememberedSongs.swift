import Foundation
import GRDB

/// Favorites, ratings, plays and playlist and mix places of songs whose music folder was removed. Kept beside
/// the database so they come back when the same songs are added again, from any folder. Songs are matched like
/// Device Sync matches them: by path below the music folder, or else by artist, title, album and length.
public struct RememberedSongs: Codable, Sendable, Equatable {
    public typealias SongKey = ProfileSnapshot.SongKey

    public struct SongState: Codable, Sendable, Equatable {
        public var key: SongKey
        public var isFavorite: Bool
        public var rating: Int?
    }

    public struct Play: Codable, Sendable, Equatable {
        public var key: SongKey
        public var playedAt: Date
    }

    /// A song's place in a playlist or saved mix (both stay when a folder is removed; only their songs go).
    public struct Place: Codable, Sendable, Equatable {
        public var listId: Int64
        public var position: Int
        public var key: SongKey
    }

    public var songs: [SongState] = []
    public var plays: [Play] = []
    public var playlistPlaces: [Place] = []
    public var mixPlaces: [Place] = []

    public init() {}

    public var isEmpty: Bool { songs.isEmpty && plays.isEmpty && playlistPlaces.isEmpty && mixPlaces.isEmpty }

    public mutating func append(_ other: RememberedSongs) {
        songs += other.songs
        plays += other.plays
        playlistPlaces += other.playlistPlaces
        mixPlaces += other.mixPlaces
    }

    // MARK: - File

    public static func load(from url: URL) -> RememberedSongs {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(RememberedSongs.self, from: data) else { return RememberedSongs() }
        return saved
    }

    public func save(to url: URL) throws {
        if isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        }
    }
}

public extension LibraryDatabase {

    /// What to keep of a folder's songs before the folder is removed.
    func rememberSongs(inFolder folderId: Int64) async throws -> RememberedSongs {
        try await writer.read { db in
            let keys = try Self.songKeys(db)
            var remembered = RememberedSongs()
            let states = try Row.fetchAll(db, sql: """
                SELECT id, isFavorite, rating FROM track
                WHERE folderId = ? AND (isFavorite = 1 OR rating IS NOT NULL)
                """, arguments: [folderId])
            remembered.songs = states.compactMap { row in
                keys[row["id"] as Int64].map { .init(key: $0, isFavorite: row["isFavorite"], rating: row["rating"]) }
            }
            let plays = try Row.fetchAll(db, sql: """
                SELECT play.trackId, play.playedAt FROM play JOIN track ON track.id = play.trackId
                WHERE track.folderId = ?
                """, arguments: [folderId])
            remembered.plays = plays.compactMap { row in
                keys[row["trackId"] as Int64].map { .init(key: $0, playedAt: row["playedAt"]) }
            }
            func places(_ table: String, _ listColumn: String) throws -> [RememberedSongs.Place] {
                try Row.fetchAll(db, sql: """
                    SELECT item.\(listColumn) AS listId, item.position, item.trackId FROM \(table) item
                    JOIN track ON track.id = item.trackId WHERE track.folderId = ?
                    """, arguments: [folderId]).compactMap { row in
                    keys[row["trackId"] as Int64].map { .init(listId: row["listId"], position: row["position"], key: $0) }
                }
            }
            remembered.playlistPlaces = try places("playlistItem", "playlistId")
            remembered.mixPlaces = try places("savedMixItem", "savedMixId")
            return remembered
        }
    }

    /// Puts back what was remembered for songs that are in the library again. Returns how many things were
    /// restored and what is still waiting for its song. Never removes anything.
    func restoreRemembered(_ remembered: RememberedSongs) async throws -> (restored: Int, left: RememberedSongs) {
        try await writer.write { db in
            var byPath: [String: Int64] = [:]
            var byFingerprint: [String: Int64] = [:]
            for (id, key) in try Self.songKeys(db) {
                byPath[key.relativePath] = byPath[key.relativePath] ?? id
                byFingerprint[key.fingerprint] = byFingerprint[key.fingerprint] ?? id
            }
            func find(_ key: RememberedSongs.SongKey) -> Int64? {
                byPath[key.relativePath] ?? byFingerprint[key.fingerprint]
            }
            var restored = 0
            var left = RememberedSongs()

            for song in remembered.songs {
                guard let id = find(song.key) else { left.songs.append(song); continue }
                if song.isFavorite {
                    try db.execute(sql: "UPDATE track SET isFavorite = 1 WHERE id = ? AND isFavorite = 0", arguments: [id])
                    restored += db.changesCount
                }
                if let rating = song.rating {
                    try db.execute(sql: "UPDATE track SET rating = ? WHERE id = ? AND rating IS NULL", arguments: [rating, id])
                    restored += db.changesCount
                }
            }

            var knownPlays = Set<String>()
            for row in try Row.fetchAll(db, sql: "SELECT trackId, playedAt FROM play") {
                let date: Date = row["playedAt"]
                knownPlays.insert("\(row["trackId"] as Int64)@\(Int(date.timeIntervalSince1970 / 60))")
            }
            for play in remembered.plays {
                guard let id = find(play.key) else { left.plays.append(play); continue }
                guard knownPlays.insert("\(id)@\(Int(play.playedAt.timeIntervalSince1970 / 60))").inserted else { continue }
                try db.execute(sql: "INSERT INTO play (trackId, playedAt) VALUES (?, ?)", arguments: [id, play.playedAt])
                try db.execute(sql: """
                    UPDATE track SET playCount = playCount + 1,
                        lastPlayedAt = CASE WHEN lastPlayedAt IS NULL OR lastPlayedAt < ? THEN ? ELSE lastPlayedAt END
                    WHERE id = ?
                    """, arguments: [play.playedAt, play.playedAt, id])
                restored += 1
            }

            // Back into the same playlist or mix at the same spot, unless the list was deleted meanwhile.
            func restorePlaces(_ places: [RememberedSongs.Place], table: String, listTable: String,
                               listColumn: String) throws -> [RememberedSongs.Place] {
                var waiting: [RememberedSongs.Place] = []
                for place in places {
                    guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM \(listTable) WHERE id = ?)",
                                            arguments: [place.listId]) == true else { continue }
                    guard let id = find(place.key) else { waiting.append(place); continue }
                    let present = try Bool.fetchOne(db, sql: """
                        SELECT EXISTS(SELECT 1 FROM \(table) WHERE \(listColumn) = ? AND trackId = ?)
                        """, arguments: [place.listId, id]) == true
                    guard !present else { continue }
                    try db.execute(sql: "INSERT INTO \(table) (\(listColumn), trackId, position) VALUES (?, ?, ?)",
                                   arguments: [place.listId, id, place.position])
                    restored += 1
                }
                return waiting
            }
            left.playlistPlaces = try restorePlaces(remembered.playlistPlaces, table: "playlistItem",
                                                    listTable: "playlist", listColumn: "playlistId")
            left.mixPlaces = try restorePlaces(remembered.mixPlaces, table: "savedMixItem",
                                               listTable: "savedMix", listColumn: "savedMixId")
            return (restored, left)
        }
    }
}
