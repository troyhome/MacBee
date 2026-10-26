import MacBeeLibrary
import SwiftUI

/// Playlist Studio: browse and filter the library (or one playlist's songs) in the middle, build a playlist on the right.
/// Drag songs across, or select them and click "Add Selected" (⌘Return). Double-click or Return plays or pauses a song. The panes take a tint of the accent
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
    /// Songs (the library or a playlist) or Mixes (suggested and saved) in the middle.
    @AppStorage("studioBrowse") private var browsingMixes = false
    /// The mix whose songs are shown, when browsing mixes.
    @State private var openMix: StudioMix?
    @State private var mixMessage: String?
    /// The playlist being built (0 = none), remembered between visits.
    @AppStorage(Profiles.key("studioPlaylistId")) private var storedPlaylistId = 0
    /// Width of the playlist pane on the right, adjustable by dragging the divider.
    @AppStorage("studioPanelWidth") private var panelWidth = 380.0

    var body: some View {
        HStack(spacing: 0) {
            libraryBrowser
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(theme.modeTint)
            ColumnResizer(width: $panelWidth, range: 300...700, resizesLeftColumn: false, defaultWidth: 380)
            StudioPlaylistPanel(playlistId: targetBinding,
                                selectedTracks: shown.filter { selection.contains($0.path) },
                                candidates: shown)
                .padding(20)
                .frame(width: panelWidth)
                .background(theme.accent.opacity(0.2))
        }
        .overlay(RoundedRectangle(cornerRadius: 0).stroke(theme.modeBorder, lineWidth: 2).allowsHitTesting(false))
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Playlist Studio")
                    .font(.mbPageTitle)
                    .foregroundStyle(theme.textPrimary)
                Text("Studio mode: click Playlist Studio in the sidebar to leave")
                    .font(.mbSecondary)
                    .foregroundStyle(theme.textSecondary)
            }
            .lineLimit(1)
            Picker("Browse", selection: Binding(get: { browsingMixes }, set: { browsingMixes = $0; openMix = nil; selection = [] })) {
                Text("Songs").tag(false)
                Text("Mixes").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if browsingMixes {
                if let mix = openMix {
                    mixBanner(mix)
                } else {
                    StudioMixList { mix in openMix = mix; selection = [] }
                }
            } else {
                StudioFilterBar(filter: $model.filter, genres: model.genres)
            }
            if browsingMixes && openMix == nil {
                EmptyView()
            } else if browsingMixes {
                songList
            } else {
                songBrowser
            }
        }
    }

    /// The library's (or a playlist's) songs, with their source banner.
    @ViewBuilder
    private var songBrowser: some View {
            if let playlist = sourcePlaylist {
                sourceBanner(title: playlist.name) { PlaylistArtwork(playlist: playlist, size: 32, cornerRadius: 4) }
            } else if let smart = SmartPlaylist(playlistId: app.studioSourcePlaylistId) {
                sourceBanner(title: smart.title) {
                    Image(systemName: smart.systemImage).foregroundStyle(theme.accent).frame(width: 32, height: 32)
                }
            }
            songList
    }

    /// The song list (library, playlist or mix) with its buttons.
    @ViewBuilder
    private var songList: some View {
            HStack {
                Text(countText)
                    .font(.mbSecondary)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Menu("Make Mix") {
                    Button("From the Selected Song") { makeMix(fromSelection: true) }
                        .disabled(selection.isEmpty)
                    Button("From These Songs") { makeMix(fromSelection: false) }
                        .disabled(shown.isEmpty)
                }
                .fixedSize()
                .help("Make a mix: songs like the selected one (same and similar artists, same genre), or a shuffle of the songs shown")
                Button("Add Selected to Playlist") { addSelected() }
                    .disabled(selection.isEmpty || targetBinding.wrappedValue == nil)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Add the selected songs to the playlist on the right (⌘Return)")
            }
            List(selection: $selection) {
                ForEach(shown, id: \.path) { track in
                    TrackRow(track: track, showsArtist: true,
                             isCurrent: player.currentTrack?.path == track.path,
                             isPlaying: player.isPlaying, isFavorite: player.isFavorite(track))
                        .tag(track.path)
                        .draggable(dragPayload(for: track))
                }
            }
            .contextMenu(forSelectionType: String.self) { paths in
                let chosen = shown.filter { paths.contains($0.path) }
                if !chosen.isEmpty {
                    Button("Add to Studio Playlist") { add(chosen) }
                        .disabled(targetBinding.wrappedValue == nil)
                    Divider()
                    TrackContextMenu(tracks: chosen) { player.play(chosen) }
                }
            } primaryAction: { paths in
                // Double-click or Return: play (or pause) the song. Adding is drag, "Add Selected" or ⌘Return.
                if let index = shown.firstIndex(where: { paths.contains($0.path) }) {
                    player.playOrToggle(shown, at: index)
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if openMix == nil && model.isLoaded && model.results.isEmpty {
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
                Text("Showing playlist")
                    .font(.mbCaption)
                    .foregroundStyle(theme.textSecondary)
                Text(title)
                    .font(.mbRowTitle)
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

    /// The songs in the middle: the open mix's, or the library's (or a playlist's) matching the filters.
    private var shown: [Track] { openMix?.tracks ?? model.results }

    private var countText: String {
        if let mix = openMix { return "\(mix.tracks.count) songs in this mix" }
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
        add(shown.filter { selection.contains($0.path) })
    }

    /// "Showing mix" with the way back to the mixes, Save, and Add All.
    private func mixBanner(_ mix: StudioMix) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    openMix = nil
                    selection = []
                    mixMessage = nil
                } label: {
                    Label("All Mixes", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(theme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Showing mix").font(.mbCaption).foregroundStyle(theme.textSecondary)
                    Text(mix.title).font(.mbRowTitle).foregroundStyle(theme.textPrimary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !mix.isSaved {
                    Button("Save Mix") { save(mix) }
                        .help("Keep this mix in Saved Mixes (Collections)")
                }
                Button("Add All to Playlist") { add(mix.tracks) }
                    .disabled(targetBinding.wrappedValue == nil)
            }
            if let mixMessage { Text(mixMessage).font(.mbCaption).foregroundStyle(theme.textSecondary) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.5), lineWidth: 1))
    }

    /// A new mix from the selected song (like Make Mix from Song) or a shuffle of the songs shown.
    private func makeMix(fromSelection: Bool) {
        let source = shown
        Task {
            let mix: StudioMix
            if fromSelection, let seed = source.first(where: { selection.contains($0.path) }) {
                let songs = (try? await library.database.songMix(from: seed, count: 50)) ?? []
                mix = StudioMix(id: "new-\(UUID())", title: "\(seed.displayTitle) Mix",
                                subtitle: "Made from \(seed.displayTitle) by \(seed.displayArtist)",
                                tracks: [seed] + songs, origin: .new)
            } else {
                mix = StudioMix(id: "new-\(UUID())", title: "Studio Mix", subtitle: "A shuffle of songs picked in Playlist Studio",
                                tracks: Array(source.shuffled().prefix(100)), origin: .new)
            }
            browsingMixes = true
            openMix = mix
            selection = []
            mixMessage = nil
        }
    }

    private func save(_ mix: StudioMix) {
        Task {
            do {
                try await library.database.saveMix(title: mix.title, subtitle: mix.subtitle, trackIds: mix.tracks.compactMap(\.id))
                mixMessage = "Saved to Saved Mixes."
            } catch {
                mixMessage = error.localizedDescription
            }
        }
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
        let chosen = selection.contains(track.path) ? shown.filter { selection.contains($0.path) } : [track]
        return DragPayload.tracks(chosen.compactMap(\.id)).string
    }
}
