import AppKit
import MacBeeLibrary
import SwiftUI
import UniformTypeIdentifiers

/// One playlist: collage, name, Play / Shuffle, and its songs. Drag songs to reorder, Delete removes them,
/// and dropping songs, albums or artists onto the list adds them.
struct PlaylistDetailView: View {
    let playlistId: Int64

    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var entries: [PlaylistEntry] = []
    @State private var summary = PlaylistSummary(trackCount: 0, duration: 0, artworkIds: [])
    @State private var selection = Set<Int64>()
    @State private var dropTargeted = false

    var body: some View {
        if let playlist = store.playlist(id: playlistId) {
            content(playlist)
        } else {
            ContentUnavailableView("Playlist not found", systemImage: "music.note.list")
        }
    }

    private func content(_ playlist: Playlist) -> some View {
        List(selection: $selection) {
            header(playlist)
                .padding(.bottom, 12)
                .listRowSeparator(.hidden)
            if let capacity = playlist.capacitySeconds {
                // MiniDisc mix: how full the disc is (more tools in Playlist Studio).
                HStack(spacing: 16) {
                    CapacityBar(total: entries.map(\.track.duration).reduce(0, +), capacity: Double(capacity))
                        .frame(maxWidth: 420)
                    Button("Record to MiniDisc…", systemImage: "opticaldisc") { store.pendingMiniDisc = playlist }
                        .disabled(entries.isEmpty)
                }
                .padding(.bottom, 10)
                .listRowSeparator(.hidden)
            }
            if entries.isEmpty {
                ContentUnavailableView("No songs yet", systemImage: "music.note.list",
                                       description: Text("Drag songs, albums or artists here, or right-click them and choose Add to Playlist."))
                    .listRowSeparator(.hidden)
            }
            ForEach(entries) { entry in
                TrackRow(track: entry.track,
                         showsArtist: true,
                         isCurrent: player.currentTrack?.path == entry.track.path,
                         isPlaying: player.isPlaying,
                         isFavorite: player.isFavorite(entry.track))
                    .tag(entry.itemId)
            }
            .onMove { source, destination in
                var reordered = entries
                reordered.move(fromOffsets: source, toOffset: destination)
                entries = reordered
                Task { await store.reorder(playlistId, itemIds: reordered.map(\.itemId)) }
            }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            let chosen = entries.filter { ids.contains($0.itemId) }
            TrackContextMenu(tracks: chosen.map(\.track), onPlay: { play(from: chosen.first?.itemId) },
                             onRemoveFromPlaylist: { remove(ids) })
        } primaryAction: { ids in
            play(from: entries.first { ids.contains($0.itemId) }?.itemId)
        }
        .onDeleteCommand { remove(selection) }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).stroke(theme.accent, lineWidth: 2).padding(6).allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { strings, _ in
            let payloads = strings.compactMap(DragPayload.init(string:)).filter(\.carriesSongs)
            guard !payloads.isEmpty else { return false }
            Task {
                var tracks: [Track] = []
                for payload in payloads { tracks += await store.tracks(for: payload) }
                await store.add(tracks, to: playlistId)
            }
            return true
        } isTargeted: { dropTargeted = $0 }
        .navigationTitle(playlist.name)
        .task(id: "\(playlistId)-\(store.contentRevision)-\(library.revision)") { await load() }
    }

    private func header(_ playlist: Playlist) -> some View {
        DetailHero(label: folderLabel(playlist), title: playlist.name) {
            PlaylistArtwork(playlist: playlist, size: 220)
                .contextMenu { artworkMenu(playlist) }
        } subtitle: {
            Text("\(summary.trackCount) \(summary.trackCount == 1 ? "song" : "songs"), \(Format.minutes(summary.duration))")
        } controls: {
            PlayControls(onPlay: { player.play(entries.map(\.track)) },
                         onShuffle: { player.playShuffled(entries.map(\.track)) }) {
                PlaylistContextMenu(playlist: playlist)
            }
        } backdrop: {
            GeometryReader { geometry in
                PlaylistArtwork(playlist: playlist, size: max(geometry.size.width, geometry.size.height), cornerRadius: 0)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .padding([.horizontal, .bottom], 4)
    }

    @ViewBuilder
    private func artworkMenu(_ playlist: Playlist) -> some View {
        Button("Choose Picture…") { store.chooseArtwork(for: playlist) }
        if playlist.artworkId != nil {
            Button("Use Album Covers") { Task { await store.removeArtwork(from: playlist) } }
        }
    }

    private func folderLabel(_ playlist: Playlist) -> String {
        let path = store.folderPath(of: playlist)
        return path.isEmpty ? "Playlist" : "Playlist · \(path)"
    }

    private func load() async {
        entries = (try? await store.database.playlistEntries(playlistId: playlistId)) ?? []
        summary = (try? await store.database.playlistSummary(playlistId: playlistId)) ?? summary
        selection = selection.filter { id in entries.contains { $0.itemId == id } }
    }

    private func play(from itemId: Int64?) {
        guard let itemId, let index = entries.firstIndex(where: { $0.itemId == itemId }) else { return }
        player.play(entries.map(\.track), startAt: index)
    }

    private func remove(_ ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        entries.removeAll { ids.contains($0.itemId) }
        selection.subtract(ids)
        Task { await store.remove(Array(ids), from: playlistId) }
    }

}
