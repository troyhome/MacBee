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

    /// The songs' files aren't where the library says (drive not connected, or moved/renamed).
    struct SongsNotFound: LocalizedError {
        let missing: [URL]
        let sentOthers: Bool
        var errorDescription: String? {
            let first = missing[0]
            let what = missing.count == 1 ? "“\(first.lastPathComponent)” isn't" : "\(missing.count) songs aren't"
            let opened = sentOthers ? " The other songs were opened." : ""
            return "\(what) where MacBee expects, in \(first.deletingLastPathComponent().path). "
                + "Check that the drive is connected, or rescan the folder in Settings → Library.\(opened)"
        }
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
        // Also picks up TagBee if it was installed while MacBee was open.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.preferences.useDefaultTagEditorIfNeeded()
                _ = Task { await self?.checkForChanges() }
            }
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
        // One missing file makes macOS refuse the whole open with a misleading "TagBee.app not found".
        let found = urls.filter { dates[$0.path] != nil }
        let missing = urls.filter { dates[$0.path] == nil }
        if !found.isEmpty {
            for url in found { watched[url.path] = dates[url.path] }
            watchUntil = Date().addingTimeInterval(Self.watchDuration)
            _ = try await NSWorkspace.shared.open(found, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            startWatching()
        }
        if !missing.isEmpty { throw SongsNotFound(missing: missing, sentOthers: !found.isEmpty) }
    }

    /// For menus and buttons: opens the songs and shows any problem as an alert.
    func editShowingProblems(_ tracks: [Track]) {
        Task {
            do { try await edit(tracks) } catch { problem = error.localizedDescription }
        }
    }

    // MARK: - Covers (written by MacBee itself, so this works in the App Store sandbox too)

    struct CoverNotSaved: LocalizedError {
        let detail: String
        var errorDescription: String? { detail }
    }


    /// Embeds this cover (JPEG or PNG) into each song's file, then re-reads them so MacBee shows it.
    func setCover(_ image: Data, on tracks: [Track]) async throws {
        let paths = Array(Set(tracks.map(\.path))).sorted()
        guard !paths.isEmpty else { return }
        let failures = await Task.detached(priority: .userInitiated) {
            CoverWriter.embed(image, inFilesAt: paths)
        }.value
        _ = try? await library.refreshFiles(paths)
        if !failures.isEmpty {
            let names = failures.prefix(3).map { "\(URL(fileURLWithPath: $0.path).lastPathComponent): \($0.reason)" }
            throw CoverNotSaved(detail: "The cover couldn't be saved in \(failures.count) of \(paths.count) songs.\n"
                                + names.joined(separator: "\n"))
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

    /// Re-reads any watched file whose modification date changed. A watched file that's gone was usually renamed
    /// by the editor as it saved (TagBee can name files from their tags), so its whole folder is read again and
    /// the new files are watched instead.
    func checkForChanges() async {
        guard !watched.isEmpty else { return }
        let current = await Self.modificationDates(Array(watched.keys))
        var changed: [String] = []
        var renamedIn = Set<String>()
        for path in Array(watched.keys) {
            guard let date = current[path] else {
                watched[path] = nil
                renamedIn.insert((path as NSString).deletingLastPathComponent)
                continue
            }
            if watched[path] != date {
                watched[path] = date
                changed.append(path)
            }
        }
        changed.removeAll { renamedIn.contains(($0 as NSString).deletingLastPathComponent) }
        do {
            if !changed.isEmpty { try await library.refreshFiles(changed) }
            for folder in renamedIn where FileManager.default.fileExists(atPath: folder) {
                let files = try await library.refreshDirectory(folder)
                let dates = await Self.modificationDates(files)
                for file in files where watched[file] == nil { watched[file] = dates[file] ?? .distantPast }
            }
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
