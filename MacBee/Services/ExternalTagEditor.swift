import AppKit
import MacBeeLibrary
import Observation

/// Opens songs in the tag editor chosen in Preferences (TagBee), then watches those files and
/// re-reads their tags as soon as they're saved, so MacBee shows the changes right away.
@MainActor
@Observable
final class ExternalTagEditor: TagEditorService {
    struct NoEditorChosen: LocalizedError {
        var errorDescription: String? { "Choose your tag editor in Preferences → Tag Editor." }
    }

    /// Shown as an alert.
    var problem: String?

    @ObservationIgnored private let library: MusicLibrary
    @ObservationIgnored private let preferences: PreferencesStore
    /// Files being watched, with the modification date last seen.
    @ObservationIgnored private var watched: [String: Date] = [:]
    @ObservationIgnored private var watchUntil = Date.distantPast
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    /// How long to keep watching after opening songs.
    private static let watchDuration: TimeInterval = 60 * 60
    private static let checkInterval: Duration = .seconds(3)

    init(library: MusicLibrary, preferences: PreferencesStore) {
        self.library = library
        self.preferences = preferences
        // Coming back to MacBee from the tag editor: check right away instead of waiting.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.checkForChanges() } }
        }
    }

    /// The chosen app, if it's still installed.
    var editorURL: URL? {
        guard let path = preferences.tagEditorPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// "TagBee", for menu items.
    var editorName: String? {
        editorURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    // MARK: - TagEditorService

    func edit(_ tracks: [Track]) async throws {
        guard let app = editorURL else { throw NoEditorChosen() }
        let urls = Array(Set(tracks.map(\.url))).sorted { $0.path < $1.path }
        guard !urls.isEmpty else { return }
        let dates = await Self.modificationDates(urls.map(\.path))
        for url in urls { watched[url.path] = dates[url.path] ?? .distantPast }
        watchUntil = Date().addingTimeInterval(Self.watchDuration)
        _ = try await NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        startWatching()
    }

    /// For menus and buttons: opens the songs and shows any problem as an alert.
    func editShowingProblems(_ tracks: [Track]) {
        Task {
            do { try await edit(tracks) } catch { problem = error.localizedDescription }
        }
    }

    // MARK: - Watching for saves

    private func startWatching() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while let self, !Task.isCancelled, !self.watched.isEmpty, Date() < self.watchUntil {
                await self.checkForChanges()
                try? await Task.sleep(for: Self.checkInterval)
            }
            self?.watched = [:]
            self?.watchTask = nil
        }
    }

    /// Re-reads any watched file whose modification date changed.
    func checkForChanges() async {
        guard !watched.isEmpty else { return }
        let current = await Self.modificationDates(Array(watched.keys))
        var changed: [String] = []
        for (path, date) in current where watched[path] != nil && watched[path] != date {
            watched[path] = date
            changed.append(path)
        }
        guard !changed.isEmpty else { return }
        do {
            try await library.refreshFiles(changed)
        } catch {
            problem = "Couldn't re-read the edited songs. \(error.localizedDescription)"
        }
    }

    /// File dates are read off the main thread (the files may be on a network drive).
    private static func modificationDates(_ paths: [String]) async -> [String: Date] {
        await Task.detached(priority: .utility) {
            var result: [String: Date] = [:]
            for path in paths {
                let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
                if let date = values?.contentModificationDate { result[path] = date }
            }
            return result
        }.value
    }
}
