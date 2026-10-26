import MacBeeLibrary
import SwiftUI

/// The one menu for a playlist or folder: in the sidebar, on the Playlists page and behind the playlist page's "…".
struct PlaylistContextMenu: View {
    let playlist: Playlist
    /// A folder's "New Playlist in Folder" opens the folder first (sidebar only).
    var openFolder: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        if playlist.isFolder {
            Button("New Playlist in Folder") { openFolder?(); Task { await store.newPlaylist(inFolder: playlist.id) } }
            Button("New Folder Inside") { openFolder?(); Task { await store.newFolder(inFolder: playlist.id) } }
            Divider()
            Button("Rename…") { store.pendingRename = playlist }
            Button("Delete Folder…") { store.pendingDelete = playlist }
        } else {
            Button("Play") { Task { player.play(await tracks()) } }
            Button("Shuffle") { Task { player.playShuffled(await tracks()) } }
            Button("Play Next") { Task { player.playNext(await tracks()) } }
            Button("Add to Queue") { Task { player.addToQueue(await tracks()) } }
            Divider()
            Button("Rename…") { store.pendingRename = playlist }
            Button("Choose Picture…") { store.chooseArtwork(for: playlist) }
            if playlist.artworkId != nil {
                Button("Use Album Covers") { Task { await store.removeArtwork(from: playlist) } }
            }
            Button("Edit in Playlist Studio") {
                if let id = playlist.id { UserDefaults.standard.set(Int(id), forKey: Profiles.key("studioPlaylistId")) }
                app.go(to: .playlistStudio)
            }
            Divider()
            Button("Export Playlist…") { store.exportWithPanel(playlist) }
            Button("Record to MiniDisc…") { store.pendingMiniDisc = playlist }
            Divider()
            Button("Delete Playlist…") { store.pendingDelete = playlist }
        }
    }

    private func tracks() async -> [Track] {
        guard let id = playlist.id else { return [] }
        return (try? await store.database.playlistEntries(playlistId: id).map(\.track)) ?? []
    }
}

/// Shows the rename, delete and Record to MiniDisc dialogs that playlist menus ask for. Applied once, to the main window.
struct PlaylistActionsModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @State private var newName = ""
    @State private var miniDiscTracks: [Track] = []

    func body(content: Content) -> some View {
        @Bindable var store = store
        content
            .onChange(of: store.pendingRename) { newName = store.pendingRename?.name ?? "" }
            .alert(store.pendingRename?.isFolder == true ? "Rename Folder" : "Rename Playlist",
                   isPresented: Binding(get: { store.pendingRename != nil }, set: { if !$0 { store.pendingRename = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let playlist = store.pendingRename { Task { await store.rename(playlist, to: newName) } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(deleteTitle,
                                isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.pendingDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    guard let playlist = store.pendingDelete else { return }
                    if app.selectedPlaylistId == playlist.id { app.selectedPlaylistId = nil }
                    Task { await store.delete(playlist) }
                }
            } message: {
                Text(store.pendingDelete?.isFolder == true
                     ? "Everything inside the folder is deleted too. Your songs stay in the library."
                     : "Your songs stay in the library.")
            }
            .task(id: store.pendingMiniDisc?.id) {
                guard let id = store.pendingMiniDisc?.id else { miniDiscTracks = []; return }
                miniDiscTracks = (try? await store.database.playlistEntries(playlistId: id).map(\.track)) ?? []
            }
            .sheet(isPresented: Binding(get: { store.pendingMiniDisc != nil && !miniDiscTracks.isEmpty },
                                        set: { if !$0 { store.pendingMiniDisc = nil } })) {
                if let playlist = store.pendingMiniDisc {
                    RecordToMiniDiscSheet(title: playlist.name, tracks: miniDiscTracks, player: player,
                                          discMinutes: playlist.capacitySeconds.map { $0 / 60 })
                }
            }
            .alert("Playlists", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.message ?? "")
            }
    }

    private var deleteTitle: String {
        guard let playlist = store.pendingDelete else { return "" }
        return playlist.isFolder ? "Delete the folder “\(playlist.name)”?" : "Delete the playlist “\(playlist.name)”?"
    }
}
