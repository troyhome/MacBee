import AppKit
import MacBeeLibrary
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar's playlists: folders with disclosure triangles, plus a + menu (new playlist, new folder, import).
/// Drag playlists to reorder them or move them into folders; drop songs, albums or artists on a playlist to add them.
struct PlaylistSidebarSection: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var renaming: Playlist?
    @State private var newName = ""
    @State private var deleting: Playlist?
    @State private var headerTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if store.tree.isEmpty {
                        Text("No playlists yet")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 18)
                    }
                    ForEach(store.tree) { node in
                        PlaylistTreeRow(node: node, depth: 0, onRename: startRename, onDelete: { deleting = $0 })
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .onChange(of: store.pendingRename) {
            if let playlist = store.pendingRename {
                startRename(playlist)
                store.pendingRename = nil
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let playlist = renaming { Task { await store.rename(playlist, to: newName) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let playlist = deleting { Task { await store.delete(playlist) } }
            }
        } message: {
            Text(deleting?.isFolder == true
                 ? "Everything inside the folder is deleted too. Your songs stay in the library."
                 : "Your songs stay in the library.")
        }
        .alert("Playlists", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.message ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("PLAYLISTS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.textTertiary)
            Spacer()
            Menu {
                Button("New Playlist") { Task { await store.newPlaylist() } }
                Button("New Folder") { Task { await store.newFolder() } }
                Divider()
                Button("Import Playlist…", action: importPlaylist)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("New playlist, new folder, or import")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(headerTargeted ? theme.accent.opacity(0.25) : .clear)
            .padding(.horizontal, 8))
        // Dropping a playlist here moves it out of its folder, to the bottom of the top level.
        .dropDestination(for: String.self) { strings, _ in
            guard let first = strings.first, case let .playlist(id)? = DragPayload(string: first) else { return false }
            Task { await store.move(id, toFolder: nil, at: Int.max) }
            return true
        } isTargeted: { headerTargeted = $0 }
    }

    private var deleteTitle: String {
        guard let deleting else { return "" }
        return deleting.isFolder ? "Delete the folder “\(deleting.name)”?" : "Delete the playlist “\(deleting.name)”?"
    }

    private func startRename(_ playlist: Playlist) {
        newName = playlist.name
        renaming = playlist
    }

    private func importPlaylist() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.importM3U(from: url) }
    }
}
