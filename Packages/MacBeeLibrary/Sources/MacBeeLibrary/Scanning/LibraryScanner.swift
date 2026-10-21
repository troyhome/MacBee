import Foundation
import MacBeeAudio

/// Scans one folder at a time: finds files, works out what changed, reads tags for
/// new/changed files only, and saves in batches.
///
/// Network-safe rules:
/// - If the folder can't be reached (drive unmounted), nothing is changed.
/// - Files that disappear are only *flagged* missing, never deleted, so history survives.
/// - If the folder suddenly looks empty, removals are skipped.
/// - Tags are read a few files at a time, not all at once, to avoid flooding the network.
actor LibraryScanner {
    private let database: LibraryDatabase
    private let reader: MetadataReader
    private let concurrentReads: Int
    private let batchSize = 50

    /// Extensions MacBee can play (from the audio engine).
    private let audioExtensions: Set<String> = DecoderFactory.supportedExtensions

    init(database: LibraryDatabase, artwork: ArtworkStore, concurrentReads: Int = 6) {
        self.database = database
        self.reader = MetadataReader(artwork: artwork, folderArt: FolderArtCache(store: artwork))
        self.concurrentReads = concurrentReads
    }

    /// `force` re-reads every file's tags, not just new and changed ones.
    func scan(_ folder: MusicFolder, force: Bool = false,
              progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanReport {
        let started = Date()
        var report = ScanReport(folderPath: folder.path)
        guard let folderId = folder.id else { return report }

        guard folder.isReachable else {
            report.wasOffline = true
            return report
        }

        var status = ScanProgress(folderName: folder.name, phase: .checking, filesFound: 0, done: 0, total: 0)
        progress(status)

        // 1. Walk the folder.
        let found = try enumerateAudioFiles(in: folder.url) { count in
            status.filesFound = count
            progress(status)
        }
        // The drive may have dropped during the walk; if so, trust nothing we saw.
        guard folder.isReachable else {
            report.wasOffline = true
            return report
        }
        try Task.checkCancellation()

        // 2. Compare with the database.
        let existing = try await database.fileStates(folderId: folderId)
        let foundStamps = found.mapValues(\.stamp)
        let plan = ScanPlanner.plan(existing: existing, found: foundStamps, rereadAll: force)
        report.unchanged = plan.unchanged
        report.skippedRemovals = plan.skippedRemovals
        // Files that are gone are flagged before new ones are saved, so a file that was renamed (a tag editor
        // naming files from their tags) is recognized as the same song and keeps its plays and favorite.
        try await database.setMissing(plan.missing, true)

        // 3. Read tags for new and changed files, a few at a time, saving in batches.
        status.phase = .reading
        status.total = plan.toRead.count
        status.done = 0
        progress(status)

        var batch: [ScannedTrack] = []
        let reader = self.reader
        try await withThrowingTaskGroup(of: MetadataReader.Outcome.self) { group in
            let files = plan.toRead.compactMap { found[$0] }
            var next = 0
            while next < min(concurrentReads, files.count) {
                let file = files[next]
                group.addTask { await reader.read(file) }
                next += 1
            }

            while let outcome = try await group.next() {
                switch outcome {
                case let .success(track):
                    batch.append(track)
                case let .failure(path, _):
                    report.failedCount += 1
                    if report.failedPaths.count < 25 { report.failedPaths.append(path) }
                }
                status.done += 1
                if status.done % 10 == 0 || status.done == status.total { progress(status) }

                if batch.count >= batchSize {
                    report.add(try await database.save(batch, folderId: folderId))
                    batch.removeAll(keepingCapacity: true)
                }
                if Task.isCancelled {
                    group.cancelAll()
                    report.cancelled = true
                    break
                }
                if next < files.count {
                    let file = files[next]
                    group.addTask { await reader.read(file) }
                    next += 1
                }
            }
        }
        if !batch.isEmpty {
            report.add(try await database.save(batch, folderId: folderId))
        }

        // 4. Flag missing / restored files (skipped if the scan was cancelled).
        status.phase = .finishing
        progress(status)
        if report.cancelled || !folder.isReachable {
            // Cancelled, or the drive dropped while reading tags: keep what we saved, but flag nothing missing.
            try await database.setMissing(plan.missing, false)
            if !report.cancelled { report.wasOffline = true }
        } else {
            try await database.setMissing(plan.restored, false)
            report.missing = plan.missing.count
            report.restored = plan.restored.count
            try await database.markScanned(folderId: folderId)
        }

        report.seconds = Date().timeIntervalSince(started)
        return report
    }

    /// Re-reads tags for specific files (e.g. after they were edited in a tag editor), without walking
    /// the whole folder. Files outside the library's folders, or that can't be found, are skipped.
    /// Returns how many tracks were saved.
    func refresh(paths: [String], in folders: [MusicFolder]) async throws -> Int {
        var byFolder: [Int64: [FoundFile]] = [:]
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .creationDateKey]
        for path in paths {
            guard let folder = folders.first(where: { path.hasPrefix($0.path + "/") }), let folderId = folder.id,
                  let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys) else { continue }
            byFolder[folderId, default: []].append(FoundFile(
                path: path,
                stamp: FileStamp(size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast),
                createdAt: values.creationDate))
        }
        var saved = 0
        for (folderId, files) in byFolder {
            var batch: [ScannedTrack] = []
            for file in files {
                if case let .success(track) = await reader.read(file) { batch.append(track) }
            }
            if !batch.isEmpty {
                let counts = try await database.save(batch, folderId: folderId)
                saved += counts.added + counts.updated + counts.moved
            }
        }
        return saved
    }

    /// Lists playable files with their size and dates. Skips hidden files, including the
    /// "._" files macOS leaves on network drives.
    private func enumerateAudioFiles(in root: URL, onCount: (Int) -> Void) throws -> [String: FoundFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true } // keep going past unreadable subfolders
        ) else { return [:] }

        var result: [String: FoundFile] = [:]
        for case let url as URL in enumerator {
            guard audioExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            result[path] = FoundFile(
                path: path,
                stamp: FileStamp(size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast),
                createdAt: values.creationDate)
            if result.count % 250 == 0 {
                onCount(result.count)
                try Task.checkCancellation()
            }
        }
        onCount(result.count)
        return result
    }
}

private extension ScanReport {
    mutating func add(_ counts: LibraryDatabase.SaveCounts) {
        added += counts.added
        updated += counts.updated
        moved += counts.moved
    }
}
