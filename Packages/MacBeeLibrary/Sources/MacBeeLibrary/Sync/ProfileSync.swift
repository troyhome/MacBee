import Foundation
import GRDB

/// What one MacBee shares with another on the network (roadmap Phase 5): play counts, play history, favorites,
/// ratings and playlists. Songs are matched by their path below the music folder (the same drive layout on both
/// Macs), or else by artist, title, album and length, so different drive names don't matter.
public struct ProfileSnapshot: Codable, Sendable {
    public struct SongKey: Codable, Hashable, Sendable {
        /// Path below the music folder, lowercased, e.g. "ride/nowhere/01 seagull.flac".
        public var relativePath: String
        /// "artist|title|album|seconds", for when the paths differ.
        public var fingerprint: String
    }

    public struct SongState: Codable, Sendable {
        public var key: SongKey
        public var isFavorite: Bool
        public var rating: Int?
    }

    public struct Play: Codable, Hashable, Sendable {
        public var key: SongKey
        public var playedAt: Date
    }

    public struct PlaylistCopy: Codable, Sendable {
        /// Folder names from the top, e.g. ["Mixes", "Summer"].
        public var folders: [String]
        public var name: String
        public var songs: [SongKey]
        public var capacitySeconds: Int?
    }

    public var deviceName: String
    public var songs: [SongState] = []
    public var plays: [Play] = []
    public var playlists: [PlaylistCopy] = []
}

/// What a merge changed, for the message after syncing.
public struct ProfileMergeReport: Sendable, Equatable {
    public var playsAdded = 0
    public var favoritesAdded = 0
    public var ratingsUpdated = 0
    public var playlistsAdded = 0
    public var playlistSongsAdded = 0
    public var songsNotFound = 0

    public var summary: String {
        var parts: [String] = []
        if playsAdded > 0 { parts.append("\(playsAdded) plays") }
        if favoritesAdded > 0 { parts.append("\(favoritesAdded) favorites") }
        if ratingsUpdated > 0 { parts.append("\(ratingsUpdated) ratings") }
        if playlistsAdded > 0 { parts.append("\(playlistsAdded) new playlists") }
        if playlistSongsAdded > 0 { parts.append("\(playlistSongsAdded) playlist songs") }
        return parts.isEmpty ? "Already in step, nothing new." : "Added " + parts.joined(separator: ", ") + "."
    }
}

public extension LibraryDatabase {

    /// This Mac's plays, favorites, ratings and playlists, ready to send.
    func profileSnapshot(deviceName: String) async throws -> ProfileSnapshot {
        try await writer.read { db in
            let keys = try Self.songKeys(db)
            var snapshot = ProfileSnapshot(deviceName: deviceName)
            let states = try Row.fetchAll(db, sql: """
                SELECT id, isFavorite, rating FROM track WHERE isMissing = 0 AND (isFavorite = 1 OR rating IS NOT NULL)
                """)
            snapshot.songs = states.compactMap { row in
                keys[row["id"] as Int64].map { .init(key: $0, isFavorite: row["isFavorite"], rating: row["rating"]) }
            }
            let plays = try Row.fetchAll(db, sql: "SELECT trackId, playedAt FROM play")
            snapshot.plays = plays.compactMap { row in
                keys[row["trackId"] as Int64].map { .init(key: $0, playedAt: row["playedAt"]) }
            }
            let playlists = try Playlist.fetchAll(db)
            let byId = Dictionary(uniqueKeysWithValues: playlists.compactMap { p in p.id.map { ($0, p) } })
            func folders(of playlist: Playlist) -> [String] {
                var names: [String] = []
                var parent = playlist.parentFolderId
                while let id = parent, let folder = byId[id] {
                    names.insert(folder.name, at: 0)
                    parent = folder.parentFolderId
                }
                return names
            }
            for playlist in playlists where !playlist.isFolder {
                guard let id = playlist.id else { continue }
                let ids = try Int64.fetchAll(db, sql: "SELECT trackId FROM playlistItem WHERE playlistId = ? ORDER BY position",
                                             arguments: [id])
                snapshot.playlists.append(.init(folders: folders(of: playlist), name: playlist.name,
                                                songs: ids.compactMap { keys[$0] }, capacitySeconds: playlist.capacitySeconds))
            }
            return snapshot
        }
    }

    /// Brings another Mac's plays, favorites, ratings and playlists into this library. Nothing is deleted:
    /// plays are added if this Mac doesn't have them (same song, same minute), favorites and ratings are added,
    /// new playlists are created and songs missing from a shared playlist are added at the end.
    func mergeProfile(_ snapshot: ProfileSnapshot) async throws -> ProfileMergeReport {
        try await writer.write { db in
            var report = ProfileMergeReport()
            let keys = try Self.songKeys(db)
            var byPath: [String: Int64] = [:]
            var byFingerprint: [String: Int64] = [:]
            for (id, key) in keys {
                byPath[key.relativePath] = byPath[key.relativePath] ?? id
                byFingerprint[key.fingerprint] = byFingerprint[key.fingerprint] ?? id
            }
            func find(_ key: ProfileSnapshot.SongKey) -> Int64? {
                byPath[key.relativePath] ?? byFingerprint[key.fingerprint]
            }

            // Plays: add the ones this Mac doesn't have (matched to the minute), and count them.
            var knownPlays = Set<String>()
            for row in try Row.fetchAll(db, sql: "SELECT trackId, playedAt FROM play") {
                let date: Date = row["playedAt"]
                knownPlays.insert("\(row["trackId"] as Int64)@\(Int(date.timeIntervalSince1970 / 60))")
            }
            for play in snapshot.plays {
                guard let id = find(play.key) else { report.songsNotFound += 1; continue }
                let mark = "\(id)@\(Int(play.playedAt.timeIntervalSince1970 / 60))"
                guard knownPlays.insert(mark).inserted else { continue }
                try db.execute(sql: "INSERT INTO play (trackId, playedAt) VALUES (?, ?)", arguments: [id, play.playedAt])
                try db.execute(sql: """
                    UPDATE track SET playCount = playCount + 1,
                        lastPlayedAt = CASE WHEN lastPlayedAt IS NULL OR lastPlayedAt < ? THEN ? ELSE lastPlayedAt END
                    WHERE id = ?
                    """, arguments: [play.playedAt, play.playedAt, id])
                report.playsAdded += 1
            }

            // Favorites and ratings.
            for song in snapshot.songs {
                guard let id = find(song.key) else { continue }
                if song.isFavorite {
                    try db.execute(sql: "UPDATE track SET isFavorite = 1 WHERE id = ? AND isFavorite = 0", arguments: [id])
                    report.favoritesAdded += db.changesCount
                }
                if let rating = song.rating {
                    try db.execute(sql: "UPDATE track SET rating = ? WHERE id = ? AND (rating IS NULL OR rating < ?)",
                                   arguments: [rating, id, rating])
                    report.ratingsUpdated += db.changesCount
                }
            }

            // Playlists, matched by folder path and name.
            var playlists = try Playlist.fetchAll(db)
            func folderId(for path: [String]) throws -> Int64? {
                var parent: Int64?
                for name in path {
                    if let existing = playlists.first(where: { $0.isFolder && $0.name == name && $0.parentFolderId == parent }) {
                        parent = existing.id
                    } else {
                        let order = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM playlist WHERE parentFolderId IS ?",
                                                     arguments: [parent]) ?? 0
                        var folder = Playlist(id: nil, name: name, parentFolderId: parent, isFolder: true, sortOrder: order,
                                              createdAt: Date(), artworkId: nil)
                        try folder.insert(db)
                        playlists.append(folder)
                        parent = folder.id
                    }
                }
                return parent
            }
            for copy in snapshot.playlists {
                let parent = try folderId(for: copy.folders)
                var target = playlists.first { !$0.isFolder && $0.name == copy.name && $0.parentFolderId == parent }
                if target == nil {
                    let order = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM playlist WHERE parentFolderId IS ?",
                                                 arguments: [parent]) ?? 0
                    var created = Playlist(id: nil, name: copy.name, parentFolderId: parent, isFolder: false, sortOrder: order,
                                           createdAt: Date(), artworkId: nil, capacitySeconds: copy.capacitySeconds)
                    try created.insert(db)
                    playlists.append(created)
                    target = created
                    report.playlistsAdded += 1
                }
                guard let playlistId = target?.id else { continue }
                let have = Set(try Int64.fetchAll(db, sql: "SELECT trackId FROM playlistItem WHERE playlistId = ?", arguments: [playlistId]))
                var position = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM playlistItem WHERE playlistId = ?",
                                                 arguments: [playlistId])) ?? 0
                var added = Set<Int64>()
                for key in copy.songs {
                    guard let id = find(key), !have.contains(id), added.insert(id).inserted else { continue }
                    try db.execute(sql: "INSERT INTO playlistItem (playlistId, trackId, position) VALUES (?, ?, ?)",
                                   arguments: [playlistId, id, position])
                    position += 1
                    report.playlistSongsAdded += 1
                }
            }
            return report
        }
    }

    /// Every song's sync key.
    internal static func songKeys(_ db: Database) throws -> [Int64: ProfileSnapshot.SongKey] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT track.id, track.path, track.artist, track.title, track.displayAlbum, track.duration, folder.path AS root
            FROM track JOIN folder ON folder.id = track.folderId
            """)
        var keys: [Int64: ProfileSnapshot.SongKey] = [:]
        for row in rows {
            let path: String = row["path"]
            let root: String = row["root"]
            let relative = path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : (path as NSString).lastPathComponent
            let seconds = Int(((row["duration"] as Double?) ?? 0).rounded())
            let fingerprint = [DuplicateFinder.fingerprint(row["artist"] ?? ""), DuplicateFinder.fingerprint(row["title"] ?? ""),
                               DuplicateFinder.fingerprint(row["displayAlbum"] ?? ""), String(seconds)].joined(separator: "|")
            keys[row["id"]] = .init(relativePath: relative.lowercased(), fingerprint: fingerprint)
        }
        return keys
    }
}
