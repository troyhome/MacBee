import AppKit
import MacBeeVideo

/// Hands videos to VideoTagger (Troy's video tag editor), which imports them into its window.
enum VideoTaggerSender {
    static let bundleIdentifier = "com.troyhomenchuk.videotagger"

    /// VideoTagger, if it's installed.
    static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }

    /// What to open for a movie (its file), show (its folder, with every episode) or music video (its file).
    static func urls(for title: VideoTitle) -> [URL] {
        switch title {
        case let .movie(movie): movie.file.map { [$0.url] } ?? []
        case let .show(show): [URL(fileURLWithPath: show.folderPath, isDirectory: true)]
        case let .musicVideo(video): [video.file.url]
        }
    }

    /// Opens the files or folders in VideoTagger; ones that can't be reached right now (drive away) are left out.
    @MainActor
    static func open(_ urls: [URL]) {
        guard let app = appURL else { return }
        let reachable = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !reachable.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(reachable, withApplicationAt: app, configuration: configuration)
    }
}
