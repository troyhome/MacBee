import Foundation
import GRDB

/// Links between library songs and their files on a Plex server.
public extension LibraryDatabase {

    /// Every song with its path inside its library folder, for matching with Plex.
    func localFilesForMatching() async throws -> [PlexMatcher.LocalFile] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT track.id AS id, track.path AS path, folder.path AS folderPath
                FROM track JOIN folder ON folder.id = track.folderId
                """).compactMap { row in
                let path: String = row["path"], folderPath: String = row["folderPath"]
                guard path.hasPrefix(folderPath + "/") else { return nil }
                return PlexMatcher.LocalFile(trackId: row["id"], relativePath: String(path.dropFirst(folderPath.count + 1)))
            }
        }
    }

    /// Replaces all Plex links (after signing in or re-matching).
    func replacePlexLinks(_ links: [Int64: String]) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM plexLink")
            for (trackId, partKey) in links {
                try db.execute(sql: "INSERT INTO plexLink (trackId, partKey) VALUES (?, ?)", arguments: [trackId, partKey])
            }
        }
    }

    /// Where this song's file is on Plex, if it was matched.
    func plexPartKey(trackId: Int64) async throws -> String? {
        try await writer.read { db in
            try String.fetchOne(db, sql: "SELECT partKey FROM plexLink WHERE trackId = ?", arguments: [trackId])
        }
    }

    /// All links, track id -> part key (loaded once so playback can check them instantly).
    func plexLinksDictionary() async throws -> [Int64: String] {
        try await writer.read { db in
            var result: [Int64: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT trackId, partKey FROM plexLink") {
                result[row["trackId"]] = row["partKey"]
            }
            return result
        }
    }

    func plexLinkCount() async throws -> Int {
        try await writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plexLink") ?? 0 }
    }
}
