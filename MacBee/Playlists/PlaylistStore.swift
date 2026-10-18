import AppKit
import Foundation
import UniformTypeIdentifiers
import MacBeeLibrary
import Observation

/// Playlists and folders for the sidebar, menus and pages. Every change goes through here so all views stay in sync.
@MainActor
@Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    private(set) var tree: [PlaylistNode] = []
    /// Bumped whenever a playlist's songs change, so open playlist pages reload.
    private(set) var contentRevision = 0
    /// A playlist just created from a menu; the sidebar asks for its name.
    var pendingRename: Playlist?
    /// Shown as an alert (import results, problems).
    var message: String?

    @ObservationIgnored let library: MusicLibrary
    var database: LibraryDatabase { library.database }

    init(library: MusicLibrary) {
        self.library = library
        Task { await reload() }
    }

    func playlist(id: Int64?) -> Playlist? {
        guard let id else { return nil }
        return playlists.first { $0.id == id }
    }

    /// Real playlists (not folders), for pickers.
    var allPlaylists: [Playlist] { playlists.filter { !$0.isFolder } }

    /// "Folder › Subfolder" for a playlist, or "" at the top level.
    func folderPath(of playlist: Playlist) -> String {
        var names: [String] = []
        var parent = self.playlist(id: playlist.parentFolderId)
        while let folder = parent {
            names.insert(folder.name, at: 0)
            parent = self.playlist(id: folder.parentFolderId)
        }
        return names.joined(separator: " › ")
    }

    func reload() async {
        do {
            playlists = try await database.playlists()
            tree = PlaylistTree.build(playlists)
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - Playlists and folders

    @discardableResult
    /// Sets or clears a playlist's running-time limit (MiniDisc 74 / 80 minutes).
    func setCapacity(_ seconds: Int?, for playlistId: Int64) async {
        try? await database.setPlaylistCapacity(id: playlistId, seconds: seconds)
        await reload()
    }

    /// A MiniDisc mix: a playlist with a running-time limit (74 or 80 minutes).
    func newCapacityPlaylist(title: String, seconds: Int) async -> Playlist? {
        let date = Date().formatted(.iso8601.year().month().day())
        guard let playlist = await create(name: uniqueName("\(title) \(date)")), let id = playlist.id else { return nil }
        try? await database.setPlaylistCapacity(id: id, seconds: seconds)
        await reload()
        return self.playlist(id: id)
    }

    func create(name: String, isFolder: Bool = false, inFolder folderId: Int64? = nil) async -> Playlist? {
        do {
            let playlist = try await database.createPlaylist(name: name, isFolder: isFolder, parentFolderId: folderId)
            await reload()
            return playlist
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    /// Makes "New Playlist" (or "New Playlist 2"...) with these songs and asks for a name.
    @discardableResult
    func newPlaylist(with tracks: [Track] = [], inFolder folderId: Int64? = nil) async -> Playlist? {
        guard let playlist = await create(name: uniqueName("New Playlist"), inFolder: folderId) else { return nil }
        if !tracks.isEmpty, let id = playlist.id { await add(tracks, to: id) }
        pendingRename = playlist
        return playlist
    }

    func newFolder(inFolder folderId: Int64? = nil) async {
        if let folder = await create(name: uniqueName("New Folder"), isFolder: true, inFolder: folderId) {
            pendingRename = folder
        }
    }

    func rename(_ playlist: Playlist, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = playlist.id, !trimmed.isEmpty else { return }
        await run { try await self.database.renamePlaylist(id: id, to: trimmed) }
    }

    func delete(_ playlist: Playlist) async {
        guard let id = playlist.id else { return }
        RemovedPlaylistsLog.record(removedEntries(for: playlist))
        await run { try await self.database.deletePlaylist(id: id) }
        contentRevision += 1
    }

    /// The playlist (and, for a folder, everything inside it) as deletions to tell other Macs about.
    private func removedEntries(for playlist: Playlist) -> [ProfileSnapshot.RemovedPlaylist] {
        let folders = folderPath(of: playlist).split(separator: "›").map { $0.trimmingCharacters(in: .whitespaces) }
        var entries = [ProfileSnapshot.RemovedPlaylist(folders: folders, name: playlist.name, isFolder: playlist.isFolder,
                                                       removedAt: Date())]
        func walk(_ nodes: [PlaylistNode], path: [String]) {
            for node in nodes {
                entries.append(.init(folders: path, name: node.playlist.name, isFolder: node.playlist.isFolder, removedAt: Date()))
                walk(node.children, path: path + [node.playlist.name])
            }
        }
        if playlist.isFolder, let node = findNode(playlist.id, in: tree) { walk(node.children, path: folders + [playlist.name]) }
        return entries
    }

    private func findNode(_ id: Int64?, in nodes: [PlaylistNode]) -> PlaylistNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findNode(id, in: node.children) { return found }
        }
        return nil
    }

    func move(_ playlistId: Int64, toFolder folderId: Int64?, at index: Int) async {
        await run { try await self.database.movePlaylist(id: playlistId, toFolder: folderId, at: index) }
    }

    // MARK: - Pictures

    /// Asks for an image file and makes it the playlist's picture.
    func chooseArtwork(for playlist: Playlist) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use Picture"
        panel.message = "Choose a picture for “\(playlist.name)”."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await setArtwork(from: url, for: playlist) }
    }

    func setArtwork(from url: URL, for playlist: Playlist) async {
        guard let id = playlist.id else { return }
        do {
            let data = try Data(contentsOf: url)
            try await library.setPlaylistArtwork(playlistId: id, imageData: data)
        } catch {
            message = error.localizedDescription
        }
        await reload()
    }

    /// Goes back to the automatic collage of album covers.
    func removeArtwork(from playlist: Playlist) async {
        guard let id = playlist.id else { return }
        await run { try await self.library.setPlaylistArtwork(playlistId: id, imageData: nil) }
    }

    // MARK: - Songs

    func add(_ tracks: [Track], to playlistId: Int64, at index: Int? = nil) async {
        let ids = tracks.compactMap(\.id)
        guard !ids.isEmpty else { return }
        await run { try await self.database.addTracks(ids, toPlaylist: playlistId, at: index) }
        contentRevision += 1
    }

    func remove(_ itemIds: [Int64], from playlistId: Int64) async {
        await run { try await self.database.removeEntries(itemIds, fromPlaylist: playlistId) }
        contentRevision += 1
    }

    func reorder(_ playlistId: Int64, itemIds: [Int64]) async {
        await run { try await self.database.reorderEntries(playlistId: playlistId, itemIds: itemIds) }
        contentRevision += 1
    }

    /// The songs a drag carries (songs, a whole album or a whole artist).
    func tracks(for payload: DragPayload) async -> [Track] {
        do {
            switch payload {
            case let .tracks(ids):
                return try await database.tracks(ids: ids)
            case let .album(key):
                return try await database.tracks(inAlbum: key)
            case let .artist(key):
                var tracks: [Track] = []
                for album in try await database.albums(sortedBy: .artist, artistKey: key) {
                    tracks += try await database.tracks(inAlbum: album.albumKey)
                }
                return tracks
            case let .playlist(id):
                if let smart = SmartPlaylist(playlistId: id) { return try await database.tracks(for: smart) }
                return try await database.playlistEntries(playlistId: id).map(\.track)
            }
        } catch {
            message = error.localizedDescription
            return []
        }
    }

    // MARK: - M3U

    /// Makes a playlist from an .m3u/.m3u8 file. Songs not in the library are reported, not added.
    func importM3U(from url: URL) async {
        do {
            let paths = try M3UPlaylist.read(contentsOf: url)
            let tracks = try await database.tracks(atPaths: paths)
            let name = url.deletingPathExtension().lastPathComponent
            guard let playlist = await create(name: uniqueName(name)), let id = playlist.id else { return }
            await add(tracks, to: id)
            let skipped = paths.count - tracks.count
            message = skipped == 0
                ? "Imported “\(playlist.name)” with \(tracks.count) songs."
                : "Imported “\(playlist.name)” with \(tracks.count) songs. \(skipped) weren't found in your library."
        } catch {
            message = "Couldn't import that playlist. \(error.localizedDescription)"
        }
    }

    /// Asks where to save the playlist file (and whether to use relative or full paths), then saves it.
    /// Used by the playlist page and the playlists' right-click menus.
    func exportWithPanel(_ playlist: Playlist) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ["m3u8", "m3u"].compactMap { UTType(filenameExtension: $0) }
        panel.nameFieldStringValue = playlist.name + ".m3u8"
        panel.message = "Relative paths work when the playlist moves with the music or is opened from another computer."
        let style = NSPopUpButton(frame: .zero, pullsDown: false)
        style.addItems(withTitles: ["Relative paths (from where you save it)", "Full paths"])
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Song paths:"), style])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = accessory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let pathStyle: M3UPlaylist.PathStyle = style.indexOfSelectedItem == 1 ? .absolute : .relative
        Task { await exportM3U(playlist, to: url, style: pathStyle) }
    }

    func exportM3U(_ playlist: Playlist, to url: URL, style: M3UPlaylist.PathStyle = .relative) async {
        guard let id = playlist.id else { return }
        do {
            let tracks = try await database.playlistEntries(playlistId: id).map(\.track)
            let text = M3UPlaylist.export(tracks, relativeTo: url.deletingLastPathComponent(), style: style)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            message = "Couldn't export “\(playlist.name)”. \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func uniqueName(_ base: String) -> String {
        let names = Set(playlists.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        do {
            try await work()
        } catch {
            message = error.localizedDescription
        }
        await reload()
    }
}
