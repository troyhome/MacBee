import Foundation
import GRDB

/// Roadmap Phase 2: folder priority, paused folders, duplicates and failover copies.
public extension LibraryDatabase {

    /// Saves the folder order (first = highest priority).
    func setFolderOrder(_ ids: [Int64]) async throws {
        try await writer.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE folder SET priority = ? WHERE id = ?", arguments: [index, id])
            }
        }
    }

    func setFolderPaused(id: Int64, _ paused: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE folder SET isPaused = ? WHERE id = ?", arguments: [paused, id])
        }
    }

    /// Re-works out which songs show: songs in paused folders are left out, and of each set of duplicates
    /// only the best copy shows. Returns how many songs are hidden as duplicates.
    @discardableResult
    func refreshVisibility() async throws -> Int {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE track SET isPaused = (folderId IN (SELECT id FROM folder WHERE isPaused = 1))
                """)
            let rows = try Row.fetchAll(db, sql: """
                SELECT track.id, track.artist, track.displayAlbumArtist, track.title, track.displayAlbum,
                       track.duration, track.bitDepth, track.sampleRate, folder.priority
                FROM track JOIN folder ON folder.id = track.folderId
                WHERE track.isMissing = 0 AND track.isPaused = 0 AND track.isExcluded = 0
                """)
            let songs = rows.map { row in
                DuplicateFinder.Song(
                    id: row["id"],
                    artist: row["artist"] ?? row["displayAlbumArtist"] ?? "",
                    title: row["title"] ?? "",
                    album: row["displayAlbum"] ?? "",
                    duration: row["duration"] ?? 0,
                    folderPriority: row["priority"] ?? 0,
                    quality: Double((row["bitDepth"] as Int?) ?? 16) * ((row["sampleRate"] as Double?) ?? 44_100))
            }
            let duplicates = DuplicateFinder.duplicates(in: songs)
            try db.execute(sql: "UPDATE track SET duplicateOf = NULL WHERE duplicateOf IS NOT NULL")
            for (copy, shown) in duplicates {
                try db.execute(sql: "UPDATE track SET duplicateOf = ? WHERE id = ?", arguments: [shown, copy])
            }
            try markCompilations(db)
            return duplicates.count
        }
    }

    /// A song is on a compilation when it's tagged as one, filed under "Various Artists", or (with no album
    /// artist tag) its folder holds songs by three or more different artists, none of whom has half the songs.
    /// Many compilations aren't tagged; "feat." guests on an artist's own album don't count.
    private func markCompilations(_ db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT id, path, artist, albumArtist, isCompilation, displayAlbumArtist FROM track")
        var artistCounts: [String: [String: Int]] = [:]
        for row in rows {
            let path: String = row["path"]
            let folder = (path as NSString).deletingLastPathComponent
            artistCounts[folder, default: [:]][Self.mainArtist(row["artist"]), default: 0] += 1
        }
        func looksLikeCompilation(_ folder: String) -> Bool {
            guard let counts = artistCounts[folder], counts.count >= 3 else { return false }
            let total = counts.values.reduce(0, +)
            return Double(counts.values.max() ?? 0) < Double(total) * 0.5
        }
        var compilationIds: [Int64] = []
        for row in rows {
            let path: String = row["path"]
            let tagged: Bool = row["isCompilation"] ?? false
            let various = (row["displayAlbumArtist"] as String?) == LibraryKeys.variousArtists
            let hasAlbumArtist = !((row["albumArtist"] as String?) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            if tagged || various || (!hasAlbumArtist && looksLikeCompilation((path as NSString).deletingLastPathComponent)) {
                compilationIds.append(row["id"])
            }
        }
        try db.execute(sql: "UPDATE track SET onCompilation = 0")
        for chunk in stride(from: 0, to: compilationIds.count, by: 500) {
            let ids = compilationIds[chunk..<min(chunk + 500, compilationIds.count)]
            try db.execute(sql: "UPDATE track SET onCompilation = 1 WHERE id IN (\(ids.map(String.init).joined(separator: ",")))")
        }
    }

    /// "Slayyyter feat. Ayesha Erotica" -> "slayyyter"
    static func mainArtist(_ artist: String?) -> String {
        var name = (artist ?? "").lowercased()
        for separator in [" feat. ", " feat ", " ft. ", " featuring ", " with ", " & ", " x ", ", "] {
            if let range = name.range(of: separator) { name = String(name[..<range.lowerBound]) }
        }
        return DuplicateFinder.fingerprint(name)
    }

    /// MP3 files currently marked as compilations (see `MusicLibrary.rereadMP3Compilations`).
    func mp3CompilationPaths() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT path FROM track WHERE isCompilation = 1 AND LOWER(path) LIKE '%.mp3'")
        }
    }

    func pathsWithoutArtwork() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT path FROM track WHERE artworkId IS NULL AND isMissing = 0")
        }
    }

    // MARK: - Duplicates page

    /// Every song that has more than one copy: the copy that shows first, then the others.
    /// `accepted` lists only the groups marked as accepted (kept on purpose); otherwise those are left out.
    func duplicateGroups(accepted: Bool = false) async throws -> [DuplicateGroup] {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT track.*, folder.name AS folderName, track.duplicateAccepted AS accepted,
                       COALESCE(track.duplicateOf, track.id) AS groupId
                FROM track JOIN folder ON folder.id = track.folderId
                WHERE COALESCE(track.duplicateOf, track.id) IN (SELECT duplicateOf FROM track WHERE duplicateOf IS NOT NULL)
                  AND track.isMissing = 0 AND track.isExcluded = 0
                ORDER BY groupId, track.duplicateOf IS NOT NULL, folder.priority
                """)
            var groups: [DuplicateGroup] = []
            var acceptedCopies: [Int64: [Bool]] = [:]
            for row in rows {
                let copy = DuplicateGroup.Copy(track: try Track(row: row), folderName: row["folderName"])
                acceptedCopies[row["groupId"], default: []].append(row["accepted"])
                let groupId: Int64 = row["groupId"]
                if groups.last?.id == groupId {
                    groups[groups.count - 1].copies.append(copy)
                } else {
                    groups.append(DuplicateGroup(id: groupId, copies: [copy]))
                }
            }
            // A group counts as accepted when every copy in it was accepted.
            return groups.filter { group in
                group.copies.count > 1 && (acceptedCopies[group.id]?.allSatisfy { $0 } ?? false) == accepted
            }.sorted { a, b in
                (a.shown.artistKey, a.shown.albumKey, a.shown.discNumber ?? 0, a.shown.trackNumber ?? 0)
                    < (b.shown.artistKey, b.shown.albumKey, b.shown.discNumber ?? 0, b.shown.trackNumber ?? 0)
            }
        }
    }

    /// Marks songs' copies as accepted (kept on purpose) or not, so they stop (or start again) being listed.
    func setDuplicatesAccepted(trackIds: [Int64], _ accepted: Bool) async throws {
        try await writer.write { db in
            for id in trackIds {
                try db.execute(sql: "UPDATE track SET duplicateAccepted = ? WHERE id = ?", arguments: [accepted, id])
            }
        }
    }

    /// Takes copies out of the library for good (they stay on disk and aren't added back by scans).
    func excludeTracks(_ ids: [Int64]) async throws {
        try await writer.write { db in
            for id in ids { try db.execute(sql: "UPDATE track SET isExcluded = 1 WHERE id = ?", arguments: [id]) }
        }
    }

    /// Brings back every copy removed on the Duplicates page.
    func restoreExcludedTracks() async throws {
        try await writer.write { db in try db.execute(sql: "UPDATE track SET isExcluded = 0 WHERE isExcluded = 1") }
    }

    func excludedTrackCount() async throws -> Int {
        try await writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM track WHERE isExcluded = 1") ?? 0 }
    }

    /// Forgets songs whose files were deleted (moved to the Trash) from the Duplicates page.
    func deleteTracks(_ ids: [Int64]) async throws {
        try await writer.write { db in
            _ = try Track.filter(ids.contains(Column("id"))).deleteAll(db)
        }
    }

    /// Other copies of a song (its duplicates in other folders), best folder first, for when its own file
    /// can't be reached. Paused folders are skipped.
    func alternativeFiles(forTrackId id: Int64) async throws -> [String] {
        try await writer.read { db in
            let shownId = try Int64.fetchOne(db, sql: "SELECT COALESCE(duplicateOf, id) FROM track WHERE id = ?",
                                             arguments: [id]) ?? id
            return try String.fetchAll(db, sql: """
                SELECT track.path FROM track JOIN folder ON folder.id = track.folderId
                WHERE (track.id = ? OR track.duplicateOf = ?) AND track.id != ?
                  AND track.isMissing = 0 AND folder.isPaused = 0
                ORDER BY folder.priority, track.id
                """, arguments: [shownId, shownId, id])
        }
    }
}
