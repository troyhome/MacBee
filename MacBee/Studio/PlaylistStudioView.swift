import MacBeeLibrary
import SwiftUI

/// Playlist Studio: browse and filter the library (or one playlist's songs) in the middle, build a playlist on the right.
/// Double-click or drag songs across; "Add Selected" adds several at once. The panes take a tint of the accent
/// color so studio mode is easy to spot; clicking Playlist Studio again leaves it.
struct PlaylistStudioView: View {
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var model = StudioViewModel()
    @State private var selection = Set<String>()
    @State private var sourceTargeted = false
    /// The playlist being built (0 = none), remembered between visits.
    @AppStorage("studioPlaylistId") private var storedPlaylistId = 0
    /// Width of the playlist pane on the right, adjustable by dragging the divider.
    @AppStorage("studioPanelWidth") private var panelWidth = 380.0

    var body: some View {
        HStack(spacing: 0) {
            libraryBrowser
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(theme.accent.opacity(0.06))
            ColumnResizer(width: $panelWidth, range: 300...700, resizesLeftColumn: false, defaultWidth: 380)
            StudioPlaylistPanel(playlistId: targetBinding,
                                selectedTracks: model.results.filter { selection.contains($0.path) },
                                candidates: model.results)
                .padding(20)
                .frame(width: panelWidth)
                .background(theme.accent.opacity(0.11))
        }
        .navigationTitle("Playlist Studio")
        .onAppear { model.filter.playlistId = sourceId }
        .onChange(of: app.studioSourcePlaylistId) { model.filter.playlistId = sourceId }
        .onChange(of: store.playlists) {
            // The source playlist was deleted: go back to the whole library.
            if app.studioSourcePlaylistId != nil && sourceId == nil { app.studioSourcePlaylistId = nil }
        }
        .task(id: library.revision) { await model.loadGenres(from: library.database) }
        // A new filter cancels the previous search, so results never come back out of order.
        .task(id: SearchKey(filter: model.filter, revision: library.revision)) {
            if model.isLoaded { try? await Task.sleep(for: .milliseconds(250)) } // wait for typing to pause
            guard !Task.isCancelled else { return }
            await model.search(in: library.database)
        }
    }

    private var libraryBrowser: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Playlist Studio")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("STUDIO MODE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(theme.accent.opacity(0.7), lineWidth: 1))
                    .help("Click Playlist Studio in the sidebar to leave")
            }
            StudioFilterBar(filter: $model.filter, genres: model.genres)
            if let playlist = sourcePlaylist {
                sourceBanner(title: playlist.name) { PlaylistArtwork(playlist: playlist, size: 32, cornerRadius: 4) }
            } else if let smart = SmartPlaylist(playlistId: app.studioSourcePlaylistId) {
                sourceBanner(title: smart.title) {
                    Image(systemName: smart.systemImage).foregroundStyle(theme.accent).frame(width: 32, height: 32)
                }
            }
            HStack {
                Text(countText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button("Add Selected →") { addSelected() }
                    .disabled(selection.isEmpty || targetBinding.wrappedValue == nil)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Add the selected songs to the playlist on the right (⌘Return)")
            }
            List(selection: $selection) {
                ForEach(model.results, id: \.path) { track in
                    TrackRow(track: track, showsArtist: true,
                             isCurrent: player.currentTrack?.path == track.path,
                             isPlaying: player.isPlaying, isFavorite: player.isFavorite(track))
                        .tag(track.path)
                        .draggable(dragPayload(for: track))
                }
            }
            .contextMenu(forSelectionType: String.self) { paths in
                let chosen = model.results.filter { paths.contains($0.path) }
                if !chosen.isEmpty {
                    Button("Add to Studio Playlist") { add(chosen) }
                        .disabled(targetBinding.wrappedValue == nil)
                    Divider()
                    TrackContextMenu(tracks: chosen) { player.play(chosen) }
                }
            } primaryAction: { paths in
                add(model.results.filter { paths.contains($0.path) })
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if model.isLoaded && model.results.isEmpty {
                    ContentUnavailableView("No songs match", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Try fewer filters."))
                }
            }
            .overlay {
                if sourceTargeted {
                    RoundedRectangle(cornerRadius: 8).stroke(theme.accent, lineWidth: 2).allowsHitTesting(false)
                }
            }
            // Dropping a playlist here shows its songs, the same as clicking it in the sidebar.
            .dropDestination(for: String.self) { strings, _ in
                guard let first = strings.first, case let .playlist(id)? = DragPayload(string: first) else { return false }
                app.studioSourcePlaylistId = id
                return true
            } isTargeted: { sourceTargeted = $0 }
        }
    }

    /// "Songs from <playlist>" with a big, obvious way back to the whole library.
    private func sourceBanner<Picture: View>(title: String, @ViewBuilder picture: () -> Picture) -> some View {
        HStack(spacing: 12) {
            Button {
                app.studioSourcePlaylistId = nil
            } label: {
                Label("Back to Library", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(theme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Show songs from your whole library again")

            picture()
            VStack(alignment: .leading, spacing: 1) {
                Text("SHOWING A PLAYLIST")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.5), lineWidth: 1))
    }

    /// The playlist (or smart playlist) whose songs are shown, if it still exists.
    private var sourceId: Int64? {
        SmartPlaylist(playlistId: app.studioSourcePlaylistId)?.playlistId ?? sourcePlaylist?.id
    }

    /// The playlist whose songs are shown, if it still exists.
    private var sourcePlaylist: Playlist? {
        store.playlist(id: app.studioSourcePlaylistId).flatMap { $0.isFolder ? nil : $0 }
    }

    private var countText: String {
        let count = model.results.count
        if count >= StudioViewModel.resultLimit { return "Showing the first \(count) songs. Add filters to narrow it down." }
        return "\(count) \(count == 1 ? "song" : "songs")"
    }

    /// The target playlist, or nil when none is chosen (or it was deleted).
    private var targetBinding: Binding<Int64?> {
        Binding(get: {
            let id = Int64(storedPlaylistId)
            return store.playlist(id: id) == nil ? nil : id
        }, set: { storedPlaylistId = Int($0 ?? 0) })
    }

    private func addSelected() {
        add(model.results.filter { selection.contains($0.path) })
    }

    private func add(_ tracks: [Track]) {
        guard let id = targetBinding.wrappedValue, !tracks.isEmpty else { return }
        Task { await store.add(tracks, to: id) }
    }

    private struct SearchKey: Hashable {
        var filter: TrackFilter
        var revision: Int
    }

    private func dragPayload(for track: Track) -> String {
        let chosen = selection.contains(track.path) ? model.results.filter { selection.contains($0.path) } : [track]
        return DragPayload.tracks(chosen.compactMap(\.id)).string
    }
}
