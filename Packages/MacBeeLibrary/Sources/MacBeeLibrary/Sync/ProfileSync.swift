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

    /// A playlist (or folder) deleted on the sending Mac, so the other Mac can offer to delete it too.
    public struct RemovedPlaylist: Codable, Hashable, Sendable {
        public var folders: [String]
        public var name: String
        public var isFolder: Bool
        public var removedAt: Date
        public init(folders: [String], name: String, isFolder: Bool, removedAt: Date) {
            self.folders = folders
            self.name = name
            self.isFolder = isFolder
            self.removedAt = removedAt
        }
        /// "Mixes/Summer/Beach" style key for matching.
        public var key: String { (folders + [name]).joined(separator: "/") }
    }

    public var deviceName: String
    public var songs: [SongState] = []
    public var plays: [Play] = []
    public var playlists: [PlaylistCopy] = []
    /// Missing from older versions.
    public var removedPlaylists: [RemovedPlaylist]?
    public init(deviceName: String) { self.deviceName = deviceName }

    /// Liked movies, shows and music videos, by file or folder name (filled in by the app). Missing from older versions.
    public var likedVideos: [String]?

    /// Where each video was stopped, when it was last watched or opened (filled in by the app). Missing from older versions.
    public var videoWatching: [VideoWatchState]?

    /// Saved mixes (Collections > Saved Mixes). Missing from older versions.
    public var savedMixes: [SavedMixCopy]?

    public struct VideoWatchState: Codable, Sendable, Equatable {
        /// The file or folder name, lowercased (the same on both Macs).
        public var key: String
        public var position: Double?
        public var duration: Double?
        public var lastWatched: Date?
        public var lastPlayed: Date?
        public var watched: Bool
        public init(key: String, position: Double?, duration: Double?, lastWatched: Date?, lastPlayed: Date?, watched: Bool) {
            self.key = key
            self.position = position
            self.duration = duration
            self.lastWatched = lastWatched
            self.lastPlayed = lastPlayed
            self.watched = watched
        }
    }

    public struct SavedMixCopy: Codable, Sendable {
        public var title: String
        public var subtitle: String
        public var createdAt: Date
        public var songs: [SongKey]
    }
}

/// What a merge changed, for the message after syncing.
public struct ProfileMergeReport: Sendable, Equatable {
    public var playsAdded = 0
    public var favoritesAdded = 0
    public var ratingsUpdated = 0
    public var playlistsAdded = 0
    public var playlistSongsAdded = 0
    public var songsNotFound = 0
    public var favoritesRemoved = 0
    public var playlistsChanged = 0
    public var playlistsRemoved = 0
    /// Set by the app (video likes aren't in the music library).
    public var videoLikesChanged = 0
    /// Set by the app: videos whose watching progress came across.
    public var videoProgressChanged = 0
    public var savedMixesAdded = 0

    public init() {}

    /// Whether anything here changed (songs that couldn't be found don't count).
    public var changedSomething: Bool {
        var copy = self
        copy.songsNotFound = 0
        return copy != ProfileMergeReport()
    }

    public var summary: String {
        var parts: [String] = []
        if playsAdded > 0 { parts.append("\(playsAdded) plays") }
        if favoritesAdded > 0 { parts.append("\(favoritesAdded) favorites") }
        if ratingsUpdated > 0 { parts.append("\(ratingsUpdated) ratings") }
        if playlistsAdded > 0 { parts.append("\(playlistsAdded) new playlists") }
        if playlistSongsAdded > 0 { parts.append("\(playlistSongsAdded) playlist songs") }
        if savedMixesAdded > 0 { parts.append("\(savedMixesAdded) saved mixes") }
        var removed: [String] = []
        if favoritesRemoved > 0 { removed.append("\(favoritesRemoved) favorites") }
        if playlistsRemoved > 0 { removed.append("\(playlistsRemoved) playlists") }
        var lines: [String] = []
        if !parts.isEmpty { lines.append("Added " + parts.joined(separator: ", ") + ".") }
        if videoLikesChanged > 0 { lines.append("Changed \(videoLikesChanged) video like\(videoLikesChanged == 1 ? "" : "s").") }
        if videoProgressChanged > 0 {
            lines.append("Updated watching progress on \(videoProgressChanged) video\(videoProgressChanged == 1 ? "" : "s").")
        }
        if playlistsChanged > 0 { lines.append("Updated \(playlistsChanged) playlist\(playlistsChanged == 1 ? "" : "s").") }
        if !removed.isEmpty { lines.append("Removed " + removed.joined(separator: ", ") + ".") }
        return lines.isEmpty ? "Already in step, nothing new." : lines.joined(separator: " ")
    }
}

public extension LibraryDatabase {

    /// This Mac's plays, favorites, ratings and playlists, ready to send.
    func profileSnapshot(deviceName: String) async throws -> ProfileSnapshot {
        try await writer.read { db in
            let keys = try Self.songKeys(db)
            var snapshot = ProfileSnapshot(deviceName: deviceName)
            let states = try Row.fetchAll(db, sql: """
                SELECT id, isFavorite, rating FROM track WHERE isFavorite = 1 OR rating IS NOT NULL
                """)
            snapshot.songs = states.compactMap { row in
                keys[row["id"] as Int64].map { .init(key: $0, isFavorite: row["isFavorite"], rating: row["rating"]) }
            }
            let plays = try Row.fetchAll(db, sql: "SELECT trackId, playedAt FROM play")
            snapshot.plays = plays.compactMap { row in
                keys[row["trackId"] as Int64].map { .init(key: $0, playedAt: row["playedAt"]) }
            }
            snapshot.savedMixes = try Self.savedMixCopies(db, keys: keys)
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

    /// Makes this library match another Mac's: its favorites and playlists replace this Mac's (playlists and
    /// folders that Mac doesn't have are deleted here; the others get exactly its songs, in its order).
    /// Plays are still added, never removed, since they really happened. Back up first.
    func mirrorProfile(_ snapshot: ProfileSnapshot) async throws -> ProfileMergeReport {
        try await writer.write { db in
            try db.execute(sql: "UPDATE track SET isFavorite = 0")
            try db.execute(sql: "DELETE FROM playlistItem")
            try db.execute(sql: "DELETE FROM playlist")
        }
        return try await mergeProfile(snapshot)
    }

    /// Playlists and folders here that match ones deleted on another Mac: (what was deleted, its id here).
    func matchingPlaylists(for removed: [ProfileSnapshot.RemovedPlaylist]) async throws -> [(ProfileSnapshot.RemovedPlaylist, Int64)] {
        try await writer.read { db in
            let playlists = try Playlist.fetchAll(db)
            let byId = Dictionary(uniqueKeysWithValues: playlists.compactMap { p in p.id.map { ($0, p) } })
            func key(_ playlist: Playlist) -> String {
                var names = [playlist.name]
                var parent = playlist.parentFolderId
                while let id = parent, let folder = byId[id] {
                    names.insert(folder.name, at: 0)
                    parent = folder.parentFolderId
                }
                return names.joined(separator: "/")
            }
            var result: [(ProfileSnapshot.RemovedPlaylist, Int64)] = []
            for gone in removed {
                if let match = playlists.first(where: { $0.isFolder == gone.isFolder && key($0) == gone.key }), let id = match.id {
                    result.append((gone, id))
                }
            }
            return result
        }
    }

    /// Copies the whole library database to `url` (a safety copy before a sync replaces things).
    func backup(to url: URL) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = try DatabaseQueue(path: url.path)
        let source = writer
        try await Task.detached { try source.backup(to: destination) }.value
    }

    /// Brings another Mac's plays, favorites, ratings and playlists into this library. Nothing is deleted:
    /// plays are added if this Mac doesn't have them (same song, same minute), favorites and ratings are added,
    /// new playlists are created and songs missing from a shared playlist are added at the end.
    /// `skipping`: playlist keys ("Folder/Name") deleted on this Mac, so a sync doesn't bring them back.
    func mergeProfile(_ snapshot: ProfileSnapshot, skipping: Set<String> = []) async throws -> ProfileMergeReport {
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
            for copy in snapshot.playlists where !skipping.contains((copy.folders + [copy.name]).joined(separator: "/")) {
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

public extension LibraryDatabase {
    internal static func savedMixCopies(_ db: Database, keys: [Int64: ProfileSnapshot.SongKey]) throws -> [ProfileSnapshot.SavedMixCopy] {
        try Row.fetchAll(db, sql: "SELECT * FROM savedMix ORDER BY id").map { row in
            let id: Int64 = row["id"]
            let ids = try Int64.fetchAll(db, sql: "SELECT trackId FROM savedMixItem WHERE savedMixId = ? ORDER BY position",
                                         arguments: [id])
            return .init(title: row["title"], subtitle: row["subtitle"], createdAt: row["createdAt"],
                         songs: ids.compactMap { keys[$0] })
        }
    }

    /// Adds the other Mac's saved mixes that aren't here yet (same title, made within the same minute). Never removes any.
    func mergeSavedMixes(_ copies: [ProfileSnapshot.SavedMixCopy]) async throws -> Int {
        try await writer.write { db in
            var byPath: [String: Int64] = [:]
            var byFingerprint: [String: Int64] = [:]
            for (id, key) in try Self.songKeys(db) {
                byPath[key.relativePath] = byPath[key.relativePath] ?? id
                byFingerprint[key.fingerprint] = byFingerprint[key.fingerprint] ?? id
            }
            var known = Set<String>()
            for row in try Row.fetchAll(db, sql: "SELECT title, createdAt FROM savedMix") {
                let date: Date = row["createdAt"]
                known.insert("\(row["title"] as String)@\(Int(date.timeIntervalSince1970 / 60))")
            }
            var added = 0
            for copy in copies {
                guard known.insert("\(copy.title)@\(Int(copy.createdAt.timeIntervalSince1970 / 60))").inserted else { continue }
                let ids = copy.songs.compactMap { byPath[$0.relativePath] ?? byFingerprint[$0.fingerprint] }
                guard !ids.isEmpty else { continue }
                try db.execute(sql: "INSERT INTO savedMix (title, subtitle, createdAt) VALUES (?, ?, ?)",
                               arguments: [copy.title, copy.subtitle, copy.createdAt])
                let mixId = db.lastInsertedRowID
                for (position, trackId) in ids.enumerated() {
                    try db.execute(sql: "INSERT INTO savedMixItem (savedMixId, trackId, position) VALUES (?, ?, ?)",
                                   arguments: [mixId, trackId, position])
                }
                added += 1
            }
            return added
        }
    }
}
