import Foundation
import MacBeeAudio
import Observation

/// Where the library keeps its files.
public struct LibraryLocation: Sendable {
    public var databaseURL: URL
    public var artworkDirectory: URL

    public init(directory: URL) {
        databaseURL = directory.appendingPathComponent("Library.sqlite")
        artworkDirectory = directory.appendingPathComponent("Artwork", isDirectory: true)
    }

    /// ~/Library/Application Support/MacBee
    public static var `default`: LibraryLocation {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LibraryLocation(directory: base.appendingPathComponent("MacBee", isDirectory: true))
    }
}

public enum LibraryEvent: Sendable {
    case scanProgress(ScanProgress)
    case scanFinished([ScanReport])
    case foldersChanged
    case error(String)
}

/// The app-facing library: folders, scanning, monitoring and live stats.
/// Views read `stats`, `scanProgress` etc. and refetch lists when `revision` changes.
@MainActor
@Observable
public final class MusicLibrary {

    public struct FolderState: Identifiable, Sendable, Equatable {
        public var folder: MusicFolder
        public var isOnline: Bool
        public var isNetwork: Bool
        public var id: Int64 { folder.id ?? -1 }
    }

    public private(set) var folders: [FolderState] = []
    public private(set) var stats: LibraryStats = .empty
    /// Non-nil while a scan runs.
    public private(set) var scanProgress: ScanProgress?
    public private(set) var lastReports: [ScanReport] = []
    /// Increases whenever library contents change, so lists know to reload.
    public private(set) var revision = 0
    public private(set) var lastError: String?

    public var isScanning: Bool { scanTask != nil }

    /// How often network folders are re-checked for changes made from other computers.
    @ObservationIgnored public var periodicCheckInterval: TimeInterval? = 30 * 60 {
        didSet { monitor.setPeriodicCheck(every: periodicCheckInterval) }
    }

    @ObservationIgnored public let database: LibraryDatabase
    @ObservationIgnored public let artwork: ArtworkStore
    @ObservationIgnored public var eventHandler: (@MainActor (LibraryEvent) -> Void)?
    /// A folder's drive is now mounted somewhere else (old path, new path), so things kept by path can follow.
    @ObservationIgnored public var onFolderMoved: (@MainActor (String, String) -> Void)?

    @ObservationIgnored private let scanner: LibraryScanner
    @ObservationIgnored private let monitor = FolderMonitor()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFolderIds: [Int64] = []
    /// Folders whose next scan re-reads every file (Force Rescan).
    @ObservationIgnored private var forcedFolderIds: Set<Int64> = []
    /// Favorites, plays and playlist places of removed folders' songs, until those songs are added again.
    @ObservationIgnored private let rememberedURL: URL

    public init(location: LibraryLocation = .default) throws {
        database = try LibraryDatabase(fileURL: location.databaseURL)
        rememberedURL = location.databaseURL.deletingLastPathComponent().appendingPathComponent("RememberedSongs.json")
        artwork = ArtworkStore(directory: location.artworkDirectory)
        scanner = LibraryScanner(database: database, artwork: artwork)
        monitor.onFolderChanged = { [weak self] root in self?.folderChanged(root) }
        monitor.onVolumesChanged = { [weak self] in self?.volumesChanged() }
        monitor.onPeriodicCheck = { [weak self] in self?.scanAll() }
    }

    /// Loads folders and stats, starts watching, and (unless turned off) does a quick check for changes.
    public func start(watch: Bool = true, checkForChanges: Bool = true) async {
        FolderAccess.shared.openAll()
        await reloadFolders()
        try? await database.refreshVisibility()
        await refreshStats()
        if watch {
            monitor.watch(folders.map(\.folder.path))
            monitor.setPeriodicCheck(every: periodicCheckInterval)
        }
        if checkForChanges { scanAll() }
        await rereadMP3Compilations()
        await rereadSongsWithoutArtwork()
    }

    /// One-time fix: older versions read every MP3 with a compilation frame as a compilation, even "0" (no).
    /// Re-reads those files once so their albums leave Various Artists.
    /// Once: songs read before MacBee skipped empty embedded pictures (some files carry an empty one in front of
    /// the real cover) are read again so their covers show.
    private func rereadSongsWithoutArtwork() async {
        let key = "MacBee.rereadSongsWithoutArtwork.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard let paths = try? await database.pathsWithoutArtwork() else { return }
        let reachable = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if !reachable.isEmpty { _ = try? await refreshFiles(reachable) }
        if reachable.count == paths.count { UserDefaults.standard.set(true, forKey: key) }
    }

    private func rereadMP3Compilations() async {
        let key = "MacBee.rereadMP3Compilations.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard let paths = try? await database.mp3CompilationPaths() else { return }
        let reachable = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if !reachable.isEmpty { _ = try? await refreshFiles(reachable) }
        // Done once every file could be checked (a drive that's away gets another go next launch).
        if reachable.count == paths.count { UserDefaults.standard.set(true, forKey: key) }
    }

    // MARK: - Folders

    public func addFolder(_ url: URL) async throws {
        let path = url.standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw LibraryError.folderNotFound(path)
        }
        let existing = try await database.folders()
        if existing.contains(where: { $0.path == path }) { throw LibraryError.folderAlreadyAdded(path) }
        if let overlap = existing.first(where: { path.hasPrefix($0.path + "/") || $0.path.hasPrefix(path + "/") }) {
            throw LibraryError.folderOverlaps(path, overlap.path)
        }
        let name = FileManager.default.displayName(atPath: path)
        FolderAccess.shared.remember(url)
        let folder = try await database.insertFolder(path: path, name: name)
        if let id = folder.id, let location = VolumeLocation.identify(path) {
            try await database.setFolderVolume(id: id, volumeID: location.volumeID, pathInVolume: location.pathInVolume)
        }
        await reloadFolders()
        monitor.watch(folders.map(\.folder.path))
        emit(.foldersChanged)
        if let id = folder.id { requestScan([id]) }
    }

    /// Saves a new folder order (first = highest priority) and re-picks which copy of each duplicate shows.
    public func setFolderOrder(_ ids: [Int64]) async throws {
        try await database.setFolderOrder(ids)
        await reloadFolders()
        await applyVisibility()
    }

    /// Pauses (leaves the folder's songs out of the library, keeping the folder) or resumes a folder.
    public func setFolderPaused(id: Int64, _ paused: Bool) async throws {
        try await database.setFolderPaused(id: id, paused)
        await reloadFolders()
        await applyVisibility()
        if !paused { requestScan([id]) }
    }

    /// Takes copies out of the library for good (Duplicates page). Files stay on disk.
    public func removeFromLibrary(trackIds: [Int64]) async throws {
        try await database.excludeTracks(trackIds)
        await applyVisibility()
    }

    /// Marks duplicates as accepted (kept on purpose) so the Duplicates page stops listing them, or un-accepts them.
    public func setDuplicatesAccepted(trackIds: [Int64], _ accepted: Bool) async throws {
        try await database.setDuplicatesAccepted(trackIds: trackIds, accepted)
        revision += 1
    }

    /// Brings back every copy removed on the Duplicates page.
    public func restoreRemovedCopies() async throws {
        try await database.restoreExcludedTracks()
        await applyVisibility()
    }

    /// Forgets songs whose files were moved to the Trash.
    public func forgetDeletedFiles(trackIds: [Int64]) async throws {
        try await database.deleteTracks(trackIds)
        await applyVisibility()
    }

    /// After data came in from another Mac (plays, favorites, playlists): refreshes every list.
    public func refreshAfterSync() async {
        await applyVisibility()
    }

    /// Re-works out paused folders and duplicates, then refreshes every list.
    func applyVisibility() async {
        do {
            try await database.refreshVisibility()
        } catch {
            reportError(error)
        }
        await refreshStats()
        revision += 1
        emit(.foldersChanged)
    }

    /// Removes a folder and its tracks from the library. Files on disk are not touched.
    public func removeFolder(id: Int64) async throws {
        pendingFolderIds.removeAll { $0 == id }
        let path = folders.first { $0.folder.id == id }?.folder.path
        // Keep favorites, plays and playlist places so they come back if these songs are added again.
        var remembered = RememberedSongs.load(from: rememberedURL)
        remembered.append(try await database.rememberSongs(inFolder: id))
        try remembered.save(to: rememberedURL)
        try await database.deleteFolder(id: id)
        if let path { FolderAccess.shared.forget(path) }
        await reloadFolders()
        monitor.watch(folders.map(\.folder.path))
        await refreshStats()
        revision += 1
        emit(.foldersChanged)
    }

    /// Gives songs added again what they had before their folder was removed.
    private func restoreRememberedSongs() async {
        let remembered = RememberedSongs.load(from: rememberedURL)
        guard !remembered.isEmpty else { return }
        do {
            let result = try await database.restoreRemembered(remembered)
            if result.left != remembered { try result.left.save(to: rememberedURL) }
            if result.restored > 0 { revision += 1 }
        } catch {
            reportError(error)
        }
    }

    // MARK: - Scanning

    /// Checks every folder for new, changed and removed files (the "Scan/Refresh Library" action).
    public func scanAll() {
        requestScan(folders.filter { !$0.folder.isPaused }.compactMap(\.folder.id))
    }

    /// Force Rescan: reads every file in every folder again, even ones that look unchanged.
    /// Slower than `scanAll` (on a network drive, many minutes for a large library).
    public func forceRescanAll() {
        let ids = folders.filter { !$0.folder.isPaused }.compactMap(\.folder.id)
        forcedFolderIds.formUnion(ids)
        requestScan(ids)
    }

    /// Scans one folder: a quick check for changes, or (`readAll`) every file's tags read again.
    public func scan(folderId id: Int64, readAll: Bool = false) {
        if readAll { forcedFolderIds.insert(id) }
        requestScan([id])
    }

    /// The folder being scanned right now, if any.
    public var scanningFolderName: String? { scanProgress?.folderName }

    public func cancelScan() {
        pendingFolderIds.removeAll()
        forcedFolderIds.removeAll()
        scanTask?.cancel()
    }

    /// Waits until the current scan (and any queued ones) finish. Handy for scripts and tests.
    public func waitForScans() async {
        while let task = scanTask { await task.value }
    }

    private func requestScan(_ ids: [Int64]) {
        // Paused folders aren't scanned until they're resumed.
        let paused = Set(folders.filter(\.folder.isPaused).compactMap(\.folder.id))
        for id in ids where !pendingFolderIds.contains(id) && !paused.contains(id) { pendingFolderIds.append(id) }
        guard scanTask == nil, !pendingFolderIds.isEmpty else { return }
        scanTask = Task { await runPendingScans() }
    }

    private func runPendingScans() async {
        var reports: [ScanReport] = []
        while !pendingFolderIds.isEmpty, !Task.isCancelled {
            let id = pendingFolderIds.removeFirst()
            guard let folder = try? await database.folders().first(where: { $0.id == id }) else { continue }
            do {
                let force = forcedFolderIds.remove(id) != nil
                let report = try await scanner.scan(folder, force: force) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.scanTask != nil else { return }
                        self.scanProgress = progress
                        self.emit(.scanProgress(progress))
                    }
                }
                reports.append(report)
                if report.changedAnything {
                    await refreshStats()
                    revision += 1
                }
            } catch is CancellationError {
                break
            } catch {
                reportError(error)
            }
        }
        await reloadFolders()
        // New or changed songs may be duplicates of others (or no longer be).
        if reports.contains(where: \.changedAnything) {
            await restoreRememberedSongs()
            await applyVisibility()
        }
        scanProgress = nil
        scanTask = nil
        lastReports = reports
        emit(.scanFinished(reports))
        // Something asked for a scan while we were finishing up.
        if !pendingFolderIds.isEmpty { requestScan([]) }
    }

    // MARK: - Monitoring callbacks

    private func folderChanged(_ root: String) {
        if let id = folders.first(where: { $0.folder.path == root })?.folder.id {
            requestScan([id])
        }
    }

    private func volumesChanged() {
        Task {
            let wasOnline = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.isOnline) })
            await reloadFolders()
            // Rescan folders that just came back; restart watching so FSEvents sees remounted drives.
            let cameBack = folders.filter { $0.isOnline && wasOnline[$0.id] == false }.compactMap(\.folder.id)
            monitor.watch(folders.map(\.folder.path))
            requestScan(cameBack)
        }
    }

    // MARK: - Re-reading edited files

    /// Re-reads tags and covers for these files (e.g. after saving them in a tag editor) and updates the library.
    /// Returns how many songs were updated.
    @discardableResult
    public func refreshFiles(_ paths: [String]) async throws -> Int {
        let folderList = try await database.folders()
        let count = try await scanner.refresh(paths: paths, in: folderList)
        // Edited tags can change duplicates and compilations, so re-work those out too.
        if count > 0 { await applyVisibility() }
        return count
    }

    /// Re-reads every song in one folder (not the folders below it), for when a tag editor saved and maybe renamed
    /// its files: songs whose files are gone are marked missing first, so renamed files are recognized as the
    /// same songs (keeping plays and favorites). Returns the songs' paths now in the folder.
    @discardableResult
    public func refreshDirectory(_ folder: String) async throws -> [String] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .filter { !$0.hasPrefix(".") && DecoderFactory.supportedExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { folder + "/" + $0 }
        let present = Set(files)
        let gone = try await database.tracks(inDirectory: folder).filter { !present.contains($0.path) }.map(\.id)
        try await database.setMissing(gone, true)
        _ = try await refreshFiles(files)
        if !gone.isEmpty { await applyVisibility() }
        return files
    }

    // MARK: - Missing files

    /// Permanently removes tracks whose files are gone (and their play history). Returns how many.
    @discardableResult
    public func removeMissingTracks() async throws -> Int {
        let count = try await database.removeMissingTracks()
        if count > 0 {
            await refreshStats()
            revision += 1
        }
        return count
    }

    // MARK: - Playlist pictures

    public enum PlaylistArtworkError: LocalizedError {
        case unreadableImage
        public var errorDescription: String? { "That file isn't an image MacBee can read." }
    }

    /// Saves an image as the playlist's picture (resized and cached like album covers). Nil removes it.
    public func setPlaylistArtwork(playlistId: Int64, imageData: Data?) async throws {
        guard let imageData else {
            try await database.setPlaylistArtwork(playlistId: playlistId, to: nil)
            return
        }
        let store = artwork
        let ref = await Task.detached(priority: .userInitiated) { store.store(imageData: imageData) }.value
        guard let ref else { throw PlaylistArtworkError.unreadableImage }
        try await database.setPlaylistArtwork(playlistId: playlistId, to: ref)
    }

    // MARK: - Artwork

    /// Local file URL of a cached cover, or nil.
    public func artworkURL(for artworkId: Int64?) async -> URL? {
        guard let artworkId, let ref = try? await database.artworkRef(id: artworkId) else { return nil }
        return artwork.url(for: ref)
    }

    // MARK: - Helpers

    private func reloadFolders() async {
        do {
            await locateFolders(try await database.folders())
            let list = try await database.folders()
            folders = list.map { FolderState(folder: $0, isOnline: $0.isReachable, isNetwork: $0.isNetwork) }
        } catch {
            reportError(error)
        }
    }

    /// Folders on drives: remembers which drive each one is on, and follows a drive that's now mounted somewhere
    /// else (e.g. "/Volumes/2 Set Music-1", or the same share mounted by another app).
    private func locateFolders(_ list: [MusicFolder]) async {
        for folder in list {
            guard let id = folder.id else { continue }
            if folder.isReachable {
                // Learn the drive of folders added before MacBee remembered drives.
                if folder.volumeID == nil, let location = VolumeLocation.identify(folder.path) {
                    try? await database.setFolderVolume(id: id, volumeID: location.volumeID,
                                                        pathInVolume: location.pathInVolume)
                }
                continue
            }
            let newPath: String?
            if let volumeID = folder.volumeID, let inside = folder.pathInVolume {
                newPath = VolumeLocation.currentPath(volumeID: volumeID, pathInVolume: inside)
            } else {
                newPath = VolumeLocation.renumberedMountPath(of: folder.path)
            }
            guard let newPath, newPath != folder.path,
                  // Not if another library folder already covers that place.
                  !list.contains(where: { $0.id != id && ($0.path == newPath || newPath.hasPrefix($0.path + "/")
                                                          || $0.path.hasPrefix(newPath + "/")) })
            else { continue }
            do {
                try await database.moveFolder(id: id, to: newPath)
                FolderAccess.shared.forget(folder.path)
                FolderAccess.shared.remember(URL(fileURLWithPath: newPath, isDirectory: true))
                onFolderMoved?(folder.path, newPath)
            } catch {
                reportError(error)
            }
        }
    }

    public func refreshStats() async {
        if let newStats = try? await database.stats() { stats = newStats }
    }

    private func reportError(_ error: Error) {
        lastError = error.localizedDescription
        emit(.error(error.localizedDescription))
    }

    private func emit(_ event: LibraryEvent) {
        eventHandler?(event)
    }
}
