import Foundation
import MacBeeLibrary
import Observation

/// Where songs are played from.
enum PlaybackSourcePreference: String, CaseIterable, Identifiable {
    /// The network drive when it can be reached, otherwise Plex.
    case automatic
    case drive
    case plex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic (drive at home, Plex when away)"
        case .drive: "Always the network drive"
        case .plex: "Always Plex"
        }
    }
}

/// Decides, for each song, whether to play the file on the network drive or a copy fetched from Plex,
/// and keeps the fetched copies in a cache on this Mac.
@MainActor
@Observable
final class PlaybackRouter {
    /// A song being fetched from Plex, for the play bar ("Getting … from Plex").
    private(set) var fetchingTitle: String?
    /// Called when a song finishes downloading, so the next song can be lined up for gapless playback.
    @ObservationIgnored var onPrefetched: (() -> Void)?

    @ObservationIgnored private let plex: PlexConnection?
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private var downloads: [Int64: Task<URL, Error>] = [:]
    /// For finding another folder's copy of a song whose own file can't be reached (set by PlayerViewModel).
    @ObservationIgnored var database: LibraryDatabase?
    /// Songs whose file was unreachable: the other copy found for them (nil = none found).
    @ObservationIgnored private var backupCopies: [Int64: String?] = [:]

    private static let cacheLimitBytes: Int64 = 3_000_000_000 // 3 GB of fetched songs at most

    init(plex: PlexConnection?, preferences: PreferencesStore) {
        self.plex = plex
        self.preferences = preferences
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
    }

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee/Plex", isDirectory: true)
    }

    /// True when this file came from Plex (for the play bar indicator).
    func isFromPlex(_ url: URL?) -> Bool {
        url?.path.hasPrefix(Self.cacheDirectory.path) == true
    }

    /// Whether this URL is the one used to play `track` (drive file or Plex copy).
    func matches(_ track: Track, _ url: URL?) -> Bool {
        guard let url else { return false }
        if url == track.url || url == cacheURL(for: track) { return true }
        if let id = track.id, let backup = backupCopies[id] ?? nil { return url.path == backup }
        return false
    }

    // MARK: - Choosing the file

    /// The file to play: the song's own file; if that can't be reached, the same song in another folder
    /// (best priority first); otherwise a copy fetched from Plex (may take a few seconds).
    func playableURL(for track: Track) async throws -> URL {
        if let backup = await backupCopy(for: track) { return URL(fileURLWithPath: backup) }
        guard usePlex(for: track), let id = track.id else { return track.url }
        return try await fetch(track, id: id)
    }

    /// The file to play right now, without waiting. Nil means it's still being fetched (fetching starts).
    /// Used to line up the next song for gapless playback.
    func readyURL(for track: Track) -> URL? {
        if needsBackup(track), let id = track.id {
            guard let known = backupCopies[id] else {
                // Not looked up yet: look now, then line the song up again.
                Task { _ = await backupCopy(for: track); onPrefetched?() }
                return nil
            }
            if let path = known { return URL(fileURLWithPath: path) }
        }
        guard usePlex(for: track), let id = track.id else { return track.url }
        let cached = cacheURL(for: track)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        Task { _ = try? await fetch(track, id: id); onPrefetched?() }
        return nil
    }

    // MARK: - Another folder's copy

    /// Only when the song's own file is unreachable, and Plex isn't chosen for everything.
    private func needsBackup(_ track: Track) -> Bool {
        preferences.playbackSource != .plex && database != nil && !FileManager.default.fileExists(atPath: track.path)
    }

    /// Another folder's copy of the song that can be reached right now.
    private func backupCopy(for track: Track) async -> String? {
        guard needsBackup(track), let id = track.id, let database else { return nil }
        let candidates = (try? await database.alternativeFiles(forTrackId: id)) ?? []
        let found = candidates.first { FileManager.default.fileExists(atPath: $0) }
        backupCopies[id] = .some(found)
        return found
    }

    private func usePlex(for track: Track) -> Bool {
        guard let plex, plex.isSignedIn, let id = track.id, plex.links[id] != nil else { return false }
        switch preferences.playbackSource {
        case .drive: return false
        case .plex: return true
        case .automatic: return !FileManager.default.fileExists(atPath: track.path)
        }
    }

    // MARK: - Fetching from Plex

    private func fetch(_ track: Track, id: Int64) async throws -> URL {
        let destination = cacheURL(for: track)
        if FileManager.default.fileExists(atPath: destination.path) {
            touch(destination)
            return destination
        }
        if let running = downloads[id] { return try await running.value }
        guard let plex else { throw PlexAPI.Failure.notSignedIn }
        let partial = destination.appendingPathExtension("partial")
        let task = Task<URL, Error> {
            try await plex.download(trackId: id, to: partial)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            return destination
        }
        downloads[id] = task
        fetchingTitle = track.displayTitle
        defer {
            downloads[id] = nil
            if downloads.isEmpty { fetchingTitle = nil }
        }
        let url = try await task.value
        pruneCache()
        return url
    }

    private func cacheURL(for track: Track) -> URL {
        let ext = track.url.pathExtension.isEmpty ? "audio" : track.url.pathExtension
        return Self.cacheDirectory.appendingPathComponent("\(track.id ?? 0).\(ext)")
    }

    /// Marks a cached file as recently used, so cleaning up removes older ones first.
    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    /// Keeps the cache under its size limit by removing the least recently used songs.
    private func pruneCache() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: Self.cacheDirectory,
                                                                       includingPropertiesForKeys: Array(keys)) else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = entries.map(\.1).reduce(0, +)
        entries.sort { $0.2 < $1.2 }
        for (url, size, _) in entries where total > Self.cacheLimitBytes {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
