import MacBeeLibrary
import SwiftUI

/// Playlists as small pictures for the collapsed sidebar (folders are flattened). Click to open; drop songs to add.
struct CollapsedPlaylistIcons: View {
    @Environment(PlaylistStore.self) private var store

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(flattened(store.tree), id: \.id) { playlist in
                    CollapsedPlaylistIcon(playlist: playlist)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Every playlist in sidebar order, ignoring folders.
    private func flattened(_ nodes: [PlaylistNode]) -> [Playlist] {
        nodes.flatMap { node in node.playlist.isFolder ? flattened(node.children) : [node.playlist] }
    }
}

private struct CollapsedPlaylistIcon: View {
    let playlist: Playlist
    @Environment(AppModel.self) private var app
    @Environment(PlaylistStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var targeted = false

    private var isSelected: Bool {
        app.isPlaylistHighlighted(playlist.id)
    }

    var body: some View {
        PlaylistArtwork(playlist: playlist, size: 30, cornerRadius: 5)
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 7)
                .stroke(targeted || isSelected ? theme.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
            .onTapGesture { if let id = playlist.id { app.selectPlaylistInSidebar(id) } }
            .draggable(DragPayload.playlist(playlist.id ?? -1).string)
            .dropDestination(for: String.self) { strings, _ in
                guard let id = playlist.id else { return false }
                let payloads = strings.compactMap(DragPayload.init(string:)).filter(\.carriesSongs)
                guard !payloads.isEmpty else { return false }
                Task {
                    var tracks: [Track] = []
                    for payload in payloads { tracks += await store.tracks(for: payload) }
                    await store.add(tracks, to: id)
                }
                return true
            } isTargeted: { targeted = $0 }
            .help(playlist.name)
    }
}
