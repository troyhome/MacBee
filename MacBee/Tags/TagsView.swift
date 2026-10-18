import MacBeeLibrary
import SwiftUI

/// The Track Studio page (sidebar item "tags" in code): tools for keeping the library tidy. Duplicates lists
/// songs and videos with more than one copy;
/// TagBee opens the tag editor (fuller TagBee integration comes in roadmap Phase 5).
struct TagsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @AppStorage("tagsSection") private var section: TagsSection = .duplicates

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                if app.canGoBack {
                    CircleButton(systemImage: "chevron.left", help: "Back", tinted: false) { app.goBack() }
                }
                Text("Track Studio")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("STUDIO MODE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(theme.accent.opacity(0.7), lineWidth: 1))
                    .help("Click Track Studio in the sidebar to leave. Click a playlist in the sidebar to work on its songs.")
                PillTabs(items: TagsSection.allCases, selection: $section, title: \.title, systemImage: \.systemImage)
                Spacer()
                if let browse = app.trackStudioBrowse {
                    Button {
                        app.trackStudioBrowse = nil
                    } label: {
                        Label("Close \(browse.title)", systemImage: "sidebar.left")
                    }
                    .help("Hide \(browse.title) and give Track Studio the whole window")
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 8)

            switch section {
            case .duplicates: DuplicatesContainer()
            case .tagBee: TagBeePanel()
            case .sync: DeviceSyncView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.accent.opacity(0.06)) // tinted like Playlist Studio, so the mode is easy to spot
        .navigationTitle("Track Studio")
        .onChange(of: app.trackStudioSourcePlaylistId) { _, id in if id != nil { section = .tagBee } }
    }
}

enum TagsSection: String, CaseIterable, Identifiable {
    case duplicates, tagBee, sync
    var id: String { rawValue }
    var title: String {
        switch self {
        case .duplicates: "Duplicates"
        case .tagBee: "TagBee"
        case .sync: "Device Sync"
        }
    }
    var systemImage: String {
        switch self {
        case .duplicates: "square.on.square"
        case .tagBee: "tag"
        case .sync: "externaldrive.badge.checkmark"
        }
    }
}

/// TagBee (roadmap Phase 5): find songs, tick them and send them to TagBee; or send what's playing.
/// TagBee opens with exactly those files, and MacBee re-reads them when TagBee saves.
private struct TagBeePanel: View {
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var results: [Track] = []
    /// Songs dragged in (from Albums, Artists… beside Track Studio); shown instead of the search.
    @State private var dropped: [Track]?
    @State private var dropTargeted = false
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = sourceName {
                HStack(spacing: 10) {
                    Button {
                        dropped = nil
                        app.trackStudioSourcePlaylistId = nil
                    } label: {
                        Label("Back to Library", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.onAccent)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(theme.accent))
                    }
                    .buttonStyle(.plain)
                    Text("SHOWING A PLAYLIST")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.accent)
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
            }
            FilterField(prompt: sourceName == nil ? "Find songs, albums or artists to tag" : "Search this playlist",
                        text: $query)
                .frame(maxWidth: 420)
            // The TagBee actions, as buttons in a row under the search box.
            HStack(spacing: 8) {
                Button("Select All") { selection = Set(results.map(\.path)) }
                    .disabled(results.isEmpty)
                Button("Open \(selection.count) in TagBee") { send(results.filter { selection.contains($0.path) }) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty || !hasEditor)
                Button("Song Playing") { if let track = player.currentTrack { send([track]) } }
                    .disabled(player.currentTrack == nil || !hasEditor)
                    .help("Open the song that's playing in TagBee")
                Button("Album Playing") { Task { await sendPlayingAlbum() } }
                    .disabled(player.currentTrack == nil || !hasEditor)
                    .help("Open every song of the album that's playing in TagBee")
                Button("Open TagBee") {
                    if let path = preferences.tagEditorPath { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                }
                .disabled(!hasEditor)
                Spacer()
                Button("Clear List") { clearList() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(results.isEmpty)
                    .help("Empty the list (⌘⌫)")
            }
            List(selection: $selection) {
                ForEach(results, id: \.path) { track in
                    TrackRow(track: track, showsArtist: true,
                             isCurrent: player.currentTrack?.path == track.path,
                             isPlaying: player.isPlaying, isFavorite: player.isFavorite(track))
                        .tag(track.path)
                }
            }
            .contextMenu(forSelectionType: String.self) { paths in
                Button("Open in TagBee") { send(results.filter { paths.contains($0.path) }) }
            } primaryAction: { paths in
                send(results.filter { paths.contains($0.path) })
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 8).stroke(theme.accent, lineWidth: 2).allowsHitTesting(false)
                }
            }
            .dropDestination(for: String.self) { strings, _ in
                // Songs, albums, artists or playlists dragged from the page beside Track Studio.
                let payloads = strings.compactMap(DragPayload.init(string:))
                guard !payloads.isEmpty, let store = app.playlists else { return false }
                Task {
                    var tracks: [Track] = []
                    for payload in payloads { tracks += await store.tracks(for: payload) }
                    // Added to what's already there (each song once); Clear List starts over.
                    var list = dropped ?? []
                    let have = Set(list.map(\.path))
                    list += tracks.filter { !have.contains($0.path) }.reduce(into: [Track]()) { kept, track in
                        if !kept.contains(where: { $0.path == track.path }) { kept.append(track) }
                    }
                    dropped = list
                    results = list
                    selection.formUnion(tracks.map(\.path))
                }
                return true
            } isTargeted: { dropTargeted = $0 }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(sourceName == nil ? "Find songs to tag" : "No songs", systemImage: "tag",
                                           description: Text(hasEditor
                                               ? "Search above, click a playlist in the sidebar, or drag songs, albums or artists here. Tick songs (⌘-click or ⇧-click for several) and open them in TagBee; double-click opens one. Changes saved in TagBee show up here by themselves."
                                               : "TagBee isn't installed. Choose a tag editor in Settings > Tag Editor."))
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .onChange(of: app.trackStudioSourcePlaylistId) { dropped = nil }
        .task(id: "\(query)-\(app.trackStudioSourcePlaylistId ?? 0)-\(library.revision)-\(dropped?.count ?? -1)") {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let text = query.trimmingCharacters(in: .whitespaces)
            if let dropped {
                results = text.isEmpty ? dropped : dropped.filter {
                    [$0.displayTitle, $0.displayArtist, $0.displayAlbum].contains { $0.localizedCaseInsensitiveContains(text) }
                }
            } else if let id = app.trackStudioSourcePlaylistId {
                // A playlist from the sidebar: its songs, narrowed by the search box.
                var filter = TrackFilter()
                filter.playlistId = id
                filter.text = text
                results = (try? await library.database.tracks(matching: filter, limit: 5000)) ?? []
            } else {
                results = text.isEmpty ? [] : ((try? await library.database.search(text, limit: 500)) ?? [])
            }
            selection = selection.intersection(results.map(\.path))
        }
    }

    /// The name of the playlist (or smart playlist) clicked in the sidebar, if any.
    private var sourceName: String? {
        if dropped != nil { return "Songs dragged here" }
        guard let id = app.trackStudioSourcePlaylistId else { return nil }
        if let smart = SmartPlaylist(playlistId: id) { return smart.title }
        return app.playlists?.playlist(id: id)?.name
    }

    private var hasEditor: Bool { preferences.tagEditorPath != nil }

    /// Empties the list: dragged songs, the playlist shown, and the search.
    private func clearList() {
        dropped = nil
        app.trackStudioSourcePlaylistId = nil
        query = ""
        results = []
        selection = []
    }

    private func send(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        app.tagEditor?.editShowingProblems(tracks)
    }

    private func sendPlayingAlbum() async {
        guard let track = player.currentTrack else { return }
        let tracks = (try? await library.database.tracks(inAlbum: track.albumKey)) ?? [track]
        send(tracks)
    }
}
