import Foundation
import MacBeeLibrary

/// Playlists and folders deleted on this Mac (kept 90 days), so a sync can tell the other Mac and offer to
/// delete them there too, and so a sync doesn't bring them back here.
enum RemovedPlaylistsLog {
    private static let key = "removedPlaylists"
    private static let ignoredKey = "ignoredPlaylistRemovals"
    private static let keepFor: TimeInterval = 90 * 24 * 3600

    static var recent: [ProfileSnapshot.RemovedPlaylist] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([ProfileSnapshot.RemovedPlaylist].self, from: data) else { return [] }
        return all.filter { Date().timeIntervalSince($0.removedAt) < keepFor }
    }

    static func record(_ removed: [ProfileSnapshot.RemovedPlaylist]) {
        let all = recent + removed
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// A playlist made again (same folder and name) is no longer "deleted".
    static func forget(key playlistKey: String) {
        let all = recent.filter { $0.key != playlistKey }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Deletions from another Mac that were answered "Keep" (not asked again).
    static func isIgnored(_ removed: ProfileSnapshot.RemovedPlaylist) -> Bool {
        (UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []).contains(ignoreKey(removed))
    }

    static func ignore(_ removed: [ProfileSnapshot.RemovedPlaylist]) {
        let all = (UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []) + removed.map(ignoreKey)
        UserDefaults.standard.set(all, forKey: ignoredKey)
    }

    private static func ignoreKey(_ removed: ProfileSnapshot.RemovedPlaylist) -> String {
        "\(removed.key)@\(Int(removed.removedAt.timeIntervalSince1970))"
    }
}
