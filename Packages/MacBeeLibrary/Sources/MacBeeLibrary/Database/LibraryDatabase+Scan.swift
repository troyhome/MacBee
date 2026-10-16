import Foundation
import GRDB

/// Writes used by the scanner.
extension LibraryDatabase {

    struct SaveCounts: Sendable, Equatable {
        var added = 0
        var updated = 0
        var moved = 0
    }

    /// Size/date of every known file in a folder, keyed by path.
    func fileStates(folderId: Int64) async throws -> [String: ExistingFile] {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, path, fileSize, modifiedAt, isMissing FROM track WHERE folderId = ?
                """, arguments: [folderId])
            var result: [String: ExistingFile] = [:]
            result.reserveCapacity(rows.count)
            for row in rows {
                let path: String = row["path"]
                result[path] = ExistingFile(
                    id: row["id"],
                    stamp: FileStamp(size: row["fileSize"], modified: row["modifiedAt"]),
                    isMissing: row["isMissing"])
            }
            return result
        }
    }

    /// Inserts or updates a batch of scanned tracks in one transaction.
    /// A new file that matches a missing track (same size, title and length) is treated as a move,
    /// so its play history and favorite status are kept.
    func save(_ batch: [ScannedTrack], folderId: Int64, now: Date = Date()) async throws -> SaveCounts {
        try await writer.write { db in
            var counts = SaveCounts()
            var artworkIds: [String: Int64] = [:]

            for scanned in batch {
                var artworkId: Int64?
                if let ref = scanned.artwork {
                    if let cached = artworkIds[ref.hash] {
                        artworkId = cached
                    } else {
                        artworkId = try Self.artworkId(for: ref, db: db)
                        artworkIds[ref.hash] = artworkId
                    }
                }

                if var existing = try Track.filter(Column("path") == scanned.path).fetchOne(db) {
                    existing.apply(scanned, folderId: folderId, artworkId: artworkId)
                    try existing.update(db)
                    counts.updated += 1
                } else if var moved = try Self.findMovedTrack(for: scanned, db: db) {
                    moved.apply(scanned, folderId: folderId, artworkId: artworkId)
                    try moved.update(db)
                    counts.moved += 1
                } else {
                    var track = Track(scanned: scanned, folderId: folderId, artworkId: artworkId, now: now)
                    try track.insert(db)
                    counts.added += 1
                }
            }
            return counts
        }
    }

    func setMissing(_ ids: [Int64], _ missing: Bool) async throws {
        guard !ids.isEmpty else { return }
        try await writer.write { db in
            // Chunked to stay under SQLite's parameter limit.
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<min(start + 500, ids.count)])
                try Track.filter(chunk.contains(Column("id")))
                    .updateAll(db, Column("isMissing").set(to: missing))
            }
        }
    }

    func markScanned(folderId: Int64, at date: Date = Date()) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE folder SET lastScanAt = ? WHERE id = ?", arguments: [date, folderId])
        }
    }

    // MARK: - Helpers (inside a write transaction)

    static func artworkId(for ref: ArtworkRef, db: Database) throws -> Int64? {
        if let existing = try ArtworkRecord.filter(Column("hash") == ref.hash).fetchOne(db) {
            return existing.id
        }
        var record = ArtworkRecord(id: nil, hash: ref.hash, fileExtension: ref.fileExtension)
        try record.insert(db)
        return record.id
    }

    private static func findMovedTrack(for scanned: ScannedTrack, db: Database) throws -> Track? {
        let candidates = try Track
            .filter(Column("isMissing") == true && Column("fileSize") == scanned.fileSize)
            .fetchAll(db)
        let title = scanned.title.map(LibraryKeys.normalize)
        return candidates.first { candidate in
            candidate.title.map(LibraryKeys.normalize) == title
                && abs(candidate.duration - scanned.duration) < 1
        }
    }
}
