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
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
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
            if entries.isEmpty {
                Text("This playlist is empty. Drag songs, albums or artists here, or right-click them and choose Add to Playlist.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textTertiary)
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
        .overlay(alignment: .topLeading) {
            if app.canGoBack {
                CircleButton(systemImage: "chevron.left", help: "Back", tinted: false) { app.goBack() }
                    .padding(.leading, 20)
                    .padding(.top, 14)
            }
        }
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
        .alert("Rename Playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { Task { await store.rename(playlist, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete the playlist “\(playlist.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                app.selectedPlaylistId = nil
                Task { await store.delete(playlist) }
            }
        } message: {
            Text("Your songs stay in the library.")
        }
    }

    private func header(_ playlist: Playlist) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            PlaylistArtwork(playlist: playlist, size: 220)
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                .contextMenu { artworkMenu(playlist) }
            VStack(alignment: .leading, spacing: 6) {
                Text(folderLabel(playlist))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.textTertiary)
                Text(playlist.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                Text("\(summary.trackCount) \(summary.trackCount == 1 ? "song" : "songs"), \(Format.minutes(summary.duration))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                HStack(spacing: 12) {
                    CircleButton(systemImage: "shuffle", help: "Shuffle", diameter: 40) {
                        player.playShuffled(entries.map(\.track))
                    }
                    CircleButton(systemImage: "play.fill", help: "Play", diameter: 40) {
                        player.play(entries.map(\.track))
                    }
                    Menu {
                        Button("Rename…") { newName = playlist.name; renaming = true }
                        Button("Edit in Playlist Studio") {
                            UserDefaults.standard.set(Int(playlistId), forKey: "studioPlaylistId")
                            app.go(to: .playlistStudio)
                        }
                        Button("Export as M3U8…") { export(playlist) }
                        Divider()
                        artworkMenu(playlist)
                        Divider()
                        Button("Delete Playlist…") { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(theme.surface))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
                }
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 56) // room for the back button
        .padding([.horizontal, .bottom], 16)
        .background {
            // The playlist's colors, softly blurred, like the artist page and Now Playing.
            GeometryReader { geometry in
                PlaylistArtwork(playlist: playlist, size: max(geometry.size.width, geometry.size.height), cornerRadius: 0)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: 50)
                    .saturation(1.2)
                    .overlay(theme.background.opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        return path.isEmpty ? "PLAYLIST" : "PLAYLIST · \(path.uppercased())"
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

    private func export(_ playlist: Playlist) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        panel.nameFieldStringValue = playlist.name + ".m3u8"
        panel.message = "Save it in your music folder to use relative paths, so it also works from other computers."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.exportM3U(playlist, to: url) }
    }
}
