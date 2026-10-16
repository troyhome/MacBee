import MacBeeLibrary
import SwiftUI

/// "Add to Playlist" submenu: New Playlist… plus every playlist, with folders as submenus.
struct AddToPlaylistMenu: View {
    /// The songs to add (loaded when a playlist is picked, so albums and artists don't load up front).
    let tracks: () async -> [Track]

    var body: some View {
        Menu("Add to Playlist") {
            AddToPlaylistItems(tracks: tracks)
        }
    }
}

/// The menu items themselves, also used by the play bar's + button.
struct AddToPlaylistItems: View {
    let tracks: () async -> [Track]
    @Environment(PlaylistStore.self) private var store

    var body: some View {
        Button("New Playlist…") { Task { await store.newPlaylist(with: await tracks()) } }
        if !store.tree.isEmpty { Divider() }
        ForEach(store.tree) { node in
            AddToPlaylistNode(node: node, tracks: tracks)
        }
    }
}

private struct AddToPlaylistNode: View {
    let node: PlaylistNode
    let tracks: () async -> [Track]
    @Environment(PlaylistStore.self) private var store

    var body: some View {
        if node.playlist.isFolder {
            Menu(node.playlist.name) {
                if node.children.isEmpty {
                    Text("Empty folder")
                }
                ForEach(node.children) { AddToPlaylistNode(node: $0, tracks: tracks) }
            }
        } else {
            Button(node.playlist.name) { Task { await store.add(await tracks(), to: node.id) } }
        }
    }
}
