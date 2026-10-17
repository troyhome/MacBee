import Foundation
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

    @ObservationIgnored private let scanner: LibraryScanner
    @ObservationIgnored private let monitor = FolderMonitor()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFolderIds: [Int64] = []
    /// Folders whose next scan re-reads every file (Force Rescan).
    @ObservationIgnored private var forcedFolderIds: Set<Int64> = []

    public init(location: LibraryLocation = .default) throws {
        database = try LibraryDatabase(fileURL: location.databaseURL)
        artwork = ArtworkStore(directory: location.artworkDirectory)
        scanner = LibraryScanner(database: database, artwork: artwork)
        monitor.onFolderChanged = { [weak self] root in self?.folderChanged(root) }
        monitor.onVolumesChanged = { [weak self] in self?.volumesChanged() }
        monitor.onPeriodicCheck = { [weak self] in self?.scanAll() }
    }

    /// Loads folders and stats, starts watching, and (unless turned off) does a quick check for changes.
    public func start(watch: Bool = true, checkForChanges: Bool = true) async {
        await reloadFolders()
        await refreshStats()
        if watch {
            monitor.watch(folders.map(\.folder.path))
            monitor.setPeriodicCheck(every: periodicCheckInterval)
        }
        if checkForChanges { scanAll() }
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
        let folder = try await database.insertFolder(path: path, name: name)
        await reloadFolders()
        monitor.watch(folders.map(\.folder.path))
        emit(.foldersChanged)
        if let id = folder.id { requestScan([id]) }
    }

    /// Removes a folder and its tracks from the library. Files on disk are not touched.
    public func removeFolder(id: Int64) async throws {
        pendingFolderIds.removeAll { $0 == id }
        try await database.deleteFolder(id: id)
        await reloadFolders()
        monitor.watch(folders.map(\.folder.path))
        await refreshStats()
        revision += 1
        emit(.foldersChanged)
    }

    // MARK: - Scanning

    /// Checks every folder for new, changed and removed files (the "Scan/Refresh Library" action).
    public func scanAll() {
        requestScan(folders.compactMap(\.folder.id))
    }

    /// Force Rescan: reads every file in every folder again, even ones that look unchanged.
    /// Slower than `scanAll` (on a network drive, many minutes for a large library).
    public func forceRescanAll() {
        let ids = folders.compactMap(\.folder.id)
        forcedFolderIds.formUnion(ids)
        requestScan(ids)
    }

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
        for id in ids where !pendingFolderIds.contains(id) { pendingFolderIds.append(id) }
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
        if count > 0 {
            await refreshStats()
            revision += 1
        }
        return count
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
            let list = try await database.folders()
            folders = list.map { FolderState(folder: $0, isOnline: $0.isReachable, isNetwork: $0.isNetwork) }
        } catch {
            reportError(error)
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
