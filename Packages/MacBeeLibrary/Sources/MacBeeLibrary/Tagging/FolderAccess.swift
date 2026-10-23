import AppKit
import Foundation

/// Remembers folders the user picked, so MacBee can open them again after a restart.
///
/// In the App Store build (sandboxed) MacBee may only use folders picked in an open panel, and only while it holds
/// a security-scoped bookmark for them. Outside the sandbox the bookmarks are harmless, so both builds use this.
/// Bookmarks are kept in UserDefaults ("folderBookmarks", path -> bookmark data). Access to a folder stays open
/// while MacBee runs (a music library is read all the time); it's closed when the folder is forgotten.
@MainActor
public final class FolderAccess {
    public static let shared = FolderAccess()

    private static let defaultsKey = "folderBookmarks"
    /// Folders whose access is open right now, by the path they were picked at.
    private var open: [String: URL] = [:]
    private var mountObserver: NSObjectProtocol?

    private init() {}

    /// Saves a bookmark for a folder the user just picked, and opens access to it.
    public func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        var bookmarks = stored
        bookmarks[path] = data
        stored = bookmarks
        startAccess(path: path, data: data)
    }

    /// Closes access to a folder and drops its bookmark (the folder was removed from MacBee).
    public func forget(_ path: String) {
        open.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
        var bookmarks = stored
        bookmarks.removeValue(forKey: path)
        stored = bookmarks
    }

    /// Opens every remembered folder. Call once at launch, before scanning. Folders on a drive that isn't
    /// connected yet (the network share) are opened when it mounts.
    public func openAll() {
        for (path, data) in stored where open[path] == nil { startAccess(path: path, data: data) }
        guard mountObserver == nil else { return }
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { FolderAccess.shared.openAll() }
        }
    }

    /// True when MacBee holds a bookmark for this folder or one above it.
    public func isRemembered(_ path: String) -> Bool {
        stored.keys.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func startAccess(path: String, data: Data) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        open[path]?.stopAccessingSecurityScopedResource()
        open[path] = url
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            var bookmarks = stored
            bookmarks[path] = fresh
            stored = bookmarks
        }
    }

    private var stored: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }
}
