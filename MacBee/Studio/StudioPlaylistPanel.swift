import MacBeeLibrary
import SwiftUI

/// Right side of Playlist Studio: pick the playlist you're building and arrange its songs.
struct StudioPlaylistPanel: View {
    @Binding var playlistId: Int64?
    /// Songs selected in the studio's library list, for the tag editor button.
    var selectedTracks: [Track] = []
    /// The songs the studio's filters show now: what Auto-fill picks from for MiniDisc mixes.
    var candidates: [Track] = []

    @Environment(MusicLibrary.self) private var library
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var entries: [PlaylistEntry] = []
    @State private var selection = Set<Int64>()
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Playlist", selection: $playlistId) {
                    Text("Choose a playlist").tag(Int64?.none)
                    ForEach(store.allPlaylists) { playlist in
                        Text(label(for: playlist)).tag(playlist.id)
                    }
                }
                .labelsHidden()
                Menu("New") {
                    Button("New Playlist") {
                        Task { if let created = await store.newPlaylist() { playlistId = created.id } }
                    }
                    Divider()
                    ForEach(CapacityFiller.templates, id: \.seconds) { template in
                        Button("New \(template.title)") {
                            Task {
                                if let created = await store.newCapacityPlaylist(title: template.title, seconds: template.seconds) {
                                    playlistId = created.id
                                }
                            }
                        }
                    }
                }
                .fixedSize()
                .help("New playlist, or a MiniDisc mix limited to 74 or 80 minutes")
            }

            if let id = playlistId, let playlist = store.playlist(id: id) {
                StudioPlaylistHeader(playlist: playlist, entries: entries, candidates: candidates)
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        TrackRow(track: entry.track, showsArtist: true,
                                 isCurrent: player.currentTrack?.path == entry.track.path,
                                 isPlaying: player.isPlaying, isFavorite: player.isFavorite(entry.track))
                            .tag(entry.itemId)
                    }
                    .onMove { source, destination in
                        var reordered = entries
                        reordered.move(fromOffsets: source, toOffset: destination)
                        entries = reordered
                        Task { await store.reorder(id, itemIds: reordered.map(\.itemId)) }
                    }
                }
                .contextMenu(forSelectionType: Int64.self) { ids in
                    if !ids.isEmpty {
                        Button("Remove from Playlist") { remove(ids, from: id) }
                    }
                } primaryAction: { ids in
                    // Double-click or Return: play (or pause) from this song.
                    if let index = entries.firstIndex(where: { ids.contains($0.itemId) }) {
                        player.playOrToggle(entries.map(\.track), at: index)
                    }
                }
                .onDeleteCommand { remove(selection, from: id) }
                .scrollContentBackground(.hidden)
                .overlay {
                    if entries.isEmpty {
                        Text("Drag songs here from the left, or select them and click Add Selected.")
                            .font(.mbSecondary)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .overlay {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 8).stroke(theme.accent, lineWidth: 2).allowsHitTesting(false)
                    }
                }
                .dropDestination(for: String.self) { strings, _ in
                    // Songs, albums, artists, or a whole playlist (but not this playlist onto itself).
                    let payloads = strings.compactMap(DragPayload.init(string:)).filter { $0.carriesSongs || $0 != .playlist(id) }
                    guard !payloads.isEmpty else { return false }
                    Task {
                        var tracks: [Track] = []
                        for payload in payloads { tracks += await store.tracks(for: payload) }
                        await store.add(tracks, to: id)
                    }
                    return true
                } isTargeted: { dropTargeted = $0 }
                .task(id: "\(id)-\(store.contentRevision)-\(library.revision)") {
                    entries = (try? await store.database.playlistEntries(playlistId: id)) ?? []
                }
            } else {
                Spacer()
                Text("Pick a playlist above, or make a new one, then add songs from the left.")
                    .font(.mbSecondary)
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            TagEditorSlot(selectedTracks: selectedTracks)
        }
    }

    private func label(for playlist: Playlist) -> String {
        let path = store.folderPath(of: playlist)
        return path.isEmpty ? playlist.name : "\(path) › \(playlist.name)"
    }

    private func remove(_ ids: Set<Int64>, from playlistId: Int64) {
        guard !ids.isEmpty else { return }
        entries.removeAll { ids.contains($0.itemId) }
        selection.subtract(ids)
        Task { await store.remove(Array(ids), from: playlistId) }
    }
}

/// The playlist's picture (drop an image on it, or choose one), song count, and Play.
private struct StudioPlaylistHeader: View {
    let playlist: Playlist
    let entries: [PlaylistEntry]
    let candidates: [Track]

    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var imageTargeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlaylistArtwork(playlist: playlist, size: 84)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(imageTargeted ? theme.accent : .clear, lineWidth: 2)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    Task { await store.setArtwork(from: url, for: playlist) }
                    return true
                } isTargeted: { imageTargeted = $0 }
                .help("Drop an image here to use it as the playlist's picture")
            VStack(alignment: .leading, spacing: 6) {
                Text("\(entries.count) \(entries.count == 1 ? "song" : "songs"), \(Format.minutes(entries.map(\.track.duration).reduce(0, +)))")
                    .font(.mbSecondary)
                    .foregroundStyle(theme.textSecondary)
                HStack(spacing: 8) {
                    Button("Choose Picture…") { store.chooseArtwork(for: playlist) }
                    if playlist.artworkId != nil {
                        Button("Use Album Covers") { Task { await store.removeArtwork(from: playlist) } }
                    }
                }
                .controlSize(.small)
                HStack(spacing: 8) {
                    Button {
                        if isPlayingThis { player.togglePlayPause() } else { player.play(entries.map(\.track)) }
                    } label: {
                        Image(systemName: isPlayingThis && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(entries.isEmpty)
                    .help(isPlayingThis && player.isPlaying ? "Pause" : "Play this playlist")
                    Picker("Disc", selection: capacityBinding) {
                        Text("No time limit").tag(Int?.none)
                        ForEach(CapacityFiller.templates, id: \.seconds) { Text("MiniDisc \($0.seconds / 60) min").tag(Optional($0.seconds)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Limit the playlist to a MiniDisc's running time")
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        if let capacity = playlist.capacitySeconds {
            VStack(alignment: .leading, spacing: 8) {
                CapacityBar(total: total, capacity: Double(capacity))
                HStack {
                    Button("Auto-fill") { autoFill(capacity: Double(capacity)) }
                        .disabled(candidates.isEmpty || total >= Double(capacity) - 60)
                        .help("Adds songs from the list on the left (your filters there are the criteria) until the disc is full")
                    Text("Uses the songs your filters show on the left")
                        .font(.mbCaption)
                        .foregroundStyle(theme.textTertiary)
                }
                .controlSize(.small)
            }
        }
    }

    private var total: Double { entries.map(\.track.duration).reduce(0, +) }

    /// The song playing is one of this playlist's.
    private var isPlayingThis: Bool {
        guard let current = player.currentTrack?.path else { return false }
        return entries.contains { $0.track.path == current }
    }

    private var capacityBinding: Binding<Int?> {
        Binding(get: { playlist.capacitySeconds }, set: { seconds in
            guard let id = playlist.id else { return }
            Task { await store.setCapacity(seconds, for: id) }
        })
    }

    private func autoFill(capacity: Double) {
        guard let id = playlist.id else { return }
        let picked = CapacityFiller.fill(existing: entries.map(\.track), candidates: candidates.shuffled(), capacity: capacity)
        Task { await store.add(picked, to: id) }
    }
}
