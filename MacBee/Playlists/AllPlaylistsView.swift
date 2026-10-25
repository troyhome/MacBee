import MacBeeLibrary
import SwiftUI

/// The Playlists page: every playlist as a card, grouped by folder.
struct AllPlaylistsView: View {
    /// Shown inside the Collection page, which has its own title.
    var embedded = false
    @Environment(PlaylistStore.self) private var store
    @Environment(\.theme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Playlists", subtitle: "\(store.playlists.filter { !$0.isFolder }.count) playlists") {
                    Button("New Playlist") { Task { await store.newPlaylist() } }
                }
                .padding(.horizontal, -PageLayout.margin)
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        if !group.title.isEmpty {
                            Text(group.title)
                                .font(.mbSection)
                                .foregroundStyle(theme.textSecondary)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(group.playlists) { PlaylistCard(playlist: $0) }
                        }
                    }
                }
            }
            .padding([.horizontal, .bottom], PageLayout.margin)
        }
        .overlay {
            if store.allPlaylists.isEmpty {
                ContentUnavailableView {
                    Label("No playlists yet", systemImage: "music.note.list")
                } description: {
                    Text("Make one here or with the + next to Playlists in the sidebar. Then drag songs onto it, or right-click songs and choose Add to Playlist.")
                } actions: {
                    Button("New Playlist") { Task { await store.newPlaylist() } }
                }
            }
        }
        .navigationTitle(embedded ? "Collections" : "Playlists")
    }

    /// Top-level playlists first, then one group per folder (in sidebar order).
    private var groups: [(title: String, playlists: [Playlist])] {
        var result: [(String, [Playlist])] = []
        func walk(_ nodes: [PlaylistNode], path: String) {
            let here = nodes.filter { !$0.playlist.isFolder }.map(\.playlist)
            if !here.isEmpty { result.append((path, here)) }
            for folder in nodes where folder.playlist.isFolder {
                walk(folder.children, path: path.isEmpty ? folder.playlist.name : "\(path) › \(folder.playlist.name)")
            }
        }
        walk(store.tree, path: "")
        return result
    }
}

private struct PlaylistCard: View {
    let playlist: Playlist
    @Environment(AppModel.self) private var app
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var summary = PlaylistSummary(trackCount: 0, duration: 0, artworkIds: [])
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaylistArtwork(playlist: playlist, size: 170)
                .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 10, y: 4)
            Text(playlist.name)
                .font(.mbRowTitle)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Text("\(summary.trackCount) \(summary.trackCount == 1 ? "song" : "songs")")
                .font(.mbSecondary)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(width: 170, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering } }
        .onTapGesture(count: 2) { Task { await play(shuffled: false) } }
        .onTapGesture { if let id = playlist.id { app.openPlaylist(id) } }
        .contextMenu { PlaylistContextMenu(playlist: playlist) }
        .draggable(DragPayload.playlist(playlist.id ?? -1).string)
        .task(id: store.contentRevision) {
            if let id = playlist.id, let loaded = try? await store.database.playlistSummary(playlistId: id) { summary = loaded }
        }
    }

    private func play(shuffled: Bool) async {
        guard let id = playlist.id else { return }
        let tracks = (try? await store.database.playlistEntries(playlistId: id).map(\.track)) ?? []
        shuffled ? player.playShuffled(tracks) : player.play(tracks)
    }
}
