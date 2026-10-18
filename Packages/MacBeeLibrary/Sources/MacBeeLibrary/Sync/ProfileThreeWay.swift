import Foundation
import GRDB

/// Automatic sync between two Macs that have synced before. Each Mac keeps what its own data looked like right
/// after their last sync (its "base") and sends it along, so each side's changes since then are known, including
/// removals: un-favoriting a song, removing a song from a playlist or deleting a playlist on one Mac does the
/// same on the other instead of the other Mac bringing it back. Comparing each Mac only with its own earlier
/// self means songs one Mac doesn't have never look like removals. When both Macs changed the same playlist,
/// both sets of changes are kept.
public extension ProfileSnapshot {
    /// The state both Macs should end up with. A missing base (first automatic sync) means "nothing removed".
    static func merged(mine: ProfileSnapshot, myBase: ProfileSnapshot?,
                       theirs: ProfileSnapshot, theirBase: ProfileSnapshot?) -> ProfileSnapshot {
        var result = ProfileSnapshot(deviceName: mine.deviceName)
        let myBase = myBase ?? mine        // no base: nothing counts as removed or changed
        let theirBase = theirBase ?? theirs

        // Favorites and ratings, per song (matched by artist, title, album and length). Songs on an unplugged
        // drive are still listed, so an unplugged drive never looks like removals.
        func favorites(_ s: ProfileSnapshot) -> Set<String> { Set(s.songs.filter(\.isFavorite).map(\.key.fingerprint)) }
        func ratings(_ s: ProfileSnapshot) -> [String: Int] {
            Dictionary(s.songs.compactMap { song in song.rating.map { (song.key.fingerprint, $0) } }, uniquingKeysWith: { a, _ in a })
        }
        let favorite = combined(mine: favorites(mine), myBase: favorites(myBase),
                                theirs: favorites(theirs), theirBase: favorites(theirBase))
        let (myRatings, myBaseRatings) = (ratings(mine), ratings(myBase))
        let (theirRatings, theirBaseRatings) = (ratings(theirs), ratings(theirBase))
        var keys: [String: SongKey] = [:]
        for song in theirs.songs + mine.songs { keys[song.key.fingerprint] = song.key } // mine wins
        for id in keys.keys.sorted() {
            let rating = myRatings[id] != myBaseRatings[id] ? myRatings[id]
                : theirRatings[id] != theirBaseRatings[id] ? theirRatings[id]
                : myRatings[id] ?? theirRatings[id]
            guard favorite.contains(id) || rating != nil, let key = keys[id] else { continue }
            result.songs.append(SongState(key: key, isFavorite: favorite.contains(id), rating: rating))
        }

        // Plays really happened: all of them, once each (same song, same minute).
        var seen = Set<String>()
        for play in mine.plays + theirs.plays
        where seen.insert("\(play.key.fingerprint)@\(Int(play.playedAt.timeIntervalSince1970 / 60))").inserted {
            result.plays.append(play)
        }

        // Playlists, by folder path and name; songs added or removed on either Mac since its base.
        func byKey(_ s: ProfileSnapshot) -> [String: PlaylistCopy] {
            Dictionary(s.playlists.map { (($0.folders + [$0.name]).joined(separator: "/"), $0) }, uniquingKeysWith: { a, _ in a })
        }
        let (my, myOld, their, theirOld) = (byKey(mine), byKey(myBase), byKey(theirs), byKey(theirBase))
        for key in Set(my.keys).union(their.keys).sorted() {
            let (m, t) = (my[key], their[key])
            let myChange = !same(m, myOld[key])
            let theirChange = !same(t, theirOld[key])
            // Deleted on one Mac and left alone on the other: deleted.
            if m == nil && myOld[key] != nil && !theirChange { continue }
            if t == nil && theirOld[key] != nil && !myChange { continue }
            guard let first = (theirChange && !myChange ? t ?? m : m ?? t) else { continue }
            let second = first.songs.map(\.fingerprint) == m?.songs.map(\.fingerprint) ? t : m
            // Songs taken out on a Mac that still has the playlist (a Mac that deleted it removed nothing song by song).
            let removed = (m == nil ? [] : songs(myOld[key]).subtracting(songs(m)))
                .union(t == nil ? [] : songs(theirOld[key]).subtracting(songs(t)))
            var playlist = first
            var have = Set<String>()
            playlist.songs = (first.songs + (second?.songs ?? [])).filter { song in
                !removed.contains(song.fingerprint) && have.insert(song.fingerprint).inserted
            }
            if myChange && !theirChange { playlist.capacitySeconds = m?.capacitySeconds ?? playlist.capacitySeconds }
            if theirChange && !myChange { playlist.capacitySeconds = t?.capacitySeconds ?? playlist.capacitySeconds }
            result.playlists.append(playlist)
        }

        result.removedPlaylists = Array(Set((mine.removedPlaylists ?? []) + (theirs.removedPlaylists ?? [])))
        if let myVideos = mine.likedVideos, let theirVideos = theirs.likedVideos {
            result.likedVideos = combined(mine: Set(myVideos), myBase: Set(myBase.likedVideos ?? myVideos),
                                          theirs: Set(theirVideos), theirBase: Set(theirBase.likedVideos ?? theirVideos)).sorted()
        } else {
            result.likedVideos = mine.likedVideos ?? theirs.likedVideos
        }
        return result
    }

    /// Playlist keys ("Folder/Name") in `self` that aren't in `target`: deleted by the merge.
    func playlistKeysMissing(from target: ProfileSnapshot) -> Set<String> {
        let kept = Set(target.playlists.map { ($0.folders + [$0.name]).joined(separator: "/") })
        return Set(playlists.map { ($0.folders + [$0.name]).joined(separator: "/") }).subtracting(kept)
    }

    /// Everything either Mac has, minus what either Mac removed since its base.
    private static func combined(mine: Set<String>, myBase: Set<String>, theirs: Set<String>, theirBase: Set<String>) -> Set<String> {
        mine.union(theirs).subtracting(myBase.subtracting(mine)).subtracting(theirBase.subtracting(theirs))
    }

    private static func songs(_ playlist: PlaylistCopy?) -> Set<String> { Set(playlist?.songs.map(\.fingerprint) ?? []) }

    private static func same(_ a: PlaylistCopy?, _ b: PlaylistCopy?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return a.songs.map(\.fingerprint) == b.songs.map(\.fingerprint) && a.capacitySeconds == b.capacitySeconds
        default: return false
        }
    }
}

public extension LibraryDatabase {
    /// Makes this library match `target` by changing only what differs: favorites and ratings are set or cleared,
    /// missing plays are added, playlists get exactly the target's songs (keeping the same playlist, so nothing
    /// pointing at it breaks), new playlists are created, and the playlists named in `deleting` are removed.
    func applyProfile(_ target: ProfileSnapshot, deleting: Set<String>) async throws -> ProfileMergeReport {
        // Plays and new playlists (with their folders) go through the ordinary merge.
        var additions = target
        additions.songs = []
        var added = try await mergeProfile(additions)
        added.playlistSongsAdded = 0

        return try await writer.write { [added] db in
            var report = added
            let keys = try Self.songKeys(db)
            var byPath: [String: Int64] = [:]
            var byFingerprint: [String: Int64] = [:]
            for (id, key) in keys {
                byPath[key.relativePath] = byPath[key.relativePath] ?? id
                byFingerprint[key.fingerprint] = byFingerprint[key.fingerprint] ?? id
            }
            func find(_ key: ProfileSnapshot.SongKey) -> Int64? { byPath[key.relativePath] ?? byFingerprint[key.fingerprint] }

            // Favorites.
            let wanted = Set(target.songs.filter(\.isFavorite).compactMap { find($0.key) })
            let current = Set(try Int64.fetchAll(db, sql: "SELECT id FROM track WHERE isFavorite = 1"))
            for id in wanted.subtracting(current) {
                try db.execute(sql: "UPDATE track SET isFavorite = 1 WHERE id = ?", arguments: [id])
                report.favoritesAdded += 1
            }
            for id in current.subtracting(wanted) {
                try db.execute(sql: "UPDATE track SET isFavorite = 0 WHERE id = ?", arguments: [id])
                report.favoritesRemoved += 1
            }

            // Ratings.
            var wantedRatings: [Int64: Int] = [:]
            for song in target.songs { if let rating = song.rating, let id = find(song.key) { wantedRatings[id] = rating } }
            let rows = try Row.fetchAll(db, sql: "SELECT id, rating FROM track WHERE rating IS NOT NULL")
            let currentRatings = Dictionary(rows.map { ($0["id"] as Int64, $0["rating"] as Int) }, uniquingKeysWith: { a, _ in a })
            for (id, rating) in wantedRatings where currentRatings[id] != rating {
                try db.execute(sql: "UPDATE track SET rating = ? WHERE id = ?", arguments: [rating, id])
                report.ratingsUpdated += 1
            }
            for id in currentRatings.keys where wantedRatings[id] == nil {
                try db.execute(sql: "UPDATE track SET rating = NULL WHERE id = ?", arguments: [id])
                report.ratingsUpdated += 1
            }

            // Playlists: same songs in the same order as the target.
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
            var local: [String: Playlist] = [:]
            for playlist in playlists where !playlist.isFolder { local[key(playlist)] = local[key(playlist)] ?? playlist }
            for copy in target.playlists {
                guard var playlist = local[(copy.folders + [copy.name]).joined(separator: "/")], let id = playlist.id else { continue }
                var seen = Set<Int64>()
                let songs = copy.songs.compactMap(find).filter { seen.insert($0).inserted }
                let have = try Int64.fetchAll(db, sql: "SELECT trackId FROM playlistItem WHERE playlistId = ? ORDER BY position",
                                              arguments: [id])
                if have != songs {
                    try db.execute(sql: "DELETE FROM playlistItem WHERE playlistId = ?", arguments: [id])
                    for (position, trackId) in songs.enumerated() {
                        try db.execute(sql: "INSERT INTO playlistItem (playlistId, trackId, position) VALUES (?, ?, ?)",
                                       arguments: [id, trackId, position])
                    }
                    report.playlistsChanged += 1
                }
                if playlist.capacitySeconds != copy.capacitySeconds {
                    playlist.capacitySeconds = copy.capacitySeconds
                    try playlist.update(db)
                }
            }
            for name in deleting {
                guard let id = local[name]?.id else { continue }
                try db.execute(sql: "DELETE FROM playlistItem WHERE playlistId = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [id])
                report.playlistsRemoved += 1
            }
            return report
        }
    }
}
