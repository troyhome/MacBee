import AppKit
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                Text("STUDIO MODE")
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
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
                            .lineLimit(1)
                            .fixedSize()
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
        .background(theme.modeTint) // the studio color, like Playlist Studio, so the mode is easy to spot
        .overlay(Rectangle().stroke(theme.modeBorder, lineWidth: 2).allowsHitTesting(false))
        .navigationTitle("Track Studio")
        .onChange(of: app.trackStudioSourcePlaylistId) { _, id in if id != nil { section = .tagBee } }
    }
}

/// How Track Studio's TagBee list is organized.
enum ResultGrouping: String, CaseIterable, Identifiable {
    case songs, albums, artists
    var id: String { rawValue }
    var title: String {
        switch self {
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        }
    }
    var systemImage: String {
        switch self {
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "music.mic"
        }
    }
}

enum TagsSection: String, CaseIterable, Identifiable {
    case duplicates, tagBee, sync
    var id: String { rawValue }
    var title: String {
        switch self {
        case .duplicates: "Duplicates"
        case .tagBee: "TagBee"
        case .sync: "Copy To"
        }
    }
    var systemImage: String {
        switch self {
        case .duplicates: "square.on.square"
        case .tagBee: "tag"
        case .sync: "externaldrive.badge.plus"
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
    /// Showing every song in the library that has no artwork.
    @State private var missingArtwork = false
    /// How the list is organized: one list of songs, or sections by album or artist.
    @AppStorage("trackStudioGrouping") private var grouping: ResultGrouping = .albums
    @State private var showingWand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = sourceName {
                HStack(spacing: 10) {
                    Button {
                        dropped = nil
                        missingArtwork = false
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
                    Text(missingArtwork ? "SHOWING" : "SHOWING A PLAYLIST")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.accent)
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
            }
            FilterField(prompt: sourceName == nil ? "Find songs, albums or artists to tag"
                            : missingArtwork ? "Search the songs without artwork" : "Search this playlist",
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
                Button {
                    showingWand = true
                } label: {
                    Label("Find Covers", systemImage: "wand.and.stars")
                }
                .disabled(results.isEmpty || app.tagEditor == nil)
                .help("Look up covers online for every album in this list and choose one for each")
                Button("Missing Artwork") { showMissingArtwork() }
                    .help("List every song in the library that has no cover, grouped by album, to fix in TagBee")
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
            // Organize the results: plain list, or sections by album or artist.
            PillTabs(items: ResultGrouping.allCases, selection: $grouping, title: \.title, systemImage: \.systemImage)
                .scaleEffect(0.9, anchor: .leading)
                .opacity(results.isEmpty ? 0.5 : 1)
            List(selection: $selection) {
                switch grouping {
                case .songs:
                    ForEach(results, id: \.path) { row($0) }
                case .albums, .artists:
                    ForEach(groups, id: \.key) { group in
                        Section {
                            ForEach(group.tracks, id: \.path) { row($0) }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: String.self) { paths in
                let tracks = results.filter { paths.contains($0.path) }
                Button("Edit in TagBee") { send(tracks) }
                Divider()
                Button("Show in Library") { if let first = tracks.first { Task { await app.showInLibrary(first) } } }
                    .help("Open the song's album next to Track Studio")
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(tracks.map(\.url)) }
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
                    ContentUnavailableView(sourceName == nil ? "Find songs to tag"
                                           : missingArtwork ? "Every song has artwork" : "No songs", systemImage: "tag",
                                           description: Text(hasEditor
                                               ? "Search above, click a playlist in the sidebar, or drag songs, albums or artists here. Tick songs (⌘-click or ⇧-click for several) and open them in TagBee; double-click opens one. Changes saved in TagBee show up here by themselves."
                                               : "TagBee isn't installed. Choose a tag editor in Settings > Tag Editor."))
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .sheet(isPresented: $showingWand) { CoverWandSheet(tracks: results) }
        .onChange(of: app.trackStudioSourcePlaylistId) { _, id in
            dropped = nil
            if id != nil { missingArtwork = false }
        }
        .task(id: "\(query)-\(app.trackStudioSourcePlaylistId ?? 0)-\(library.revision)-\(dropped?.count ?? -1)-\(missingArtwork)") {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let text = query.trimmingCharacters(in: .whitespaces)
            if missingArtwork {
                // Every song without a cover (file or folder), sorted by artist and album.
                var filter = TrackFilter()
                filter.missingArtwork = true
                filter.text = text
                results = (try? await library.database.tracks(matching: filter, limit: 20000)) ?? []
            } else if let dropped {
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

    private func row(_ track: Track) -> some View {
        TrackRow(track: track, showsArtist: true,
                 isCurrent: player.currentTrack?.path == track.path,
                 isPlaying: player.isPlaying, isFavorite: player.isFavorite(track), showsArtwork: true)
            .tag(track.path)
    }

    private struct ResultGroup {
        let key: String
        let title: String
        let subtitle: String
        let artworkId: Int64?
        let tracks: [Track]
    }

    /// The results in sections, in the order they first appear.
    private var groups: [ResultGroup] {
        let byAlbum = grouping == .albums
        var order: [String] = []
        var members: [String: [Track]] = [:]
        for t in results {
            let key = byAlbum ? t.albumKey : t.artistKey
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(t)
        }
        return order.map { key in
            let list = members[key]!
            let first = list[0]
            return ResultGroup(key: key,
                               title: byAlbum ? first.displayAlbum : first.displayAlbumArtist,
                               subtitle: byAlbum ? first.displayAlbumArtist : "",
                               artworkId: list.first { $0.artworkId != nil }?.artworkId,
                               tracks: list)
        }
    }

    private func groupHeader(_ group: ResultGroup) -> some View {
        let paths = Set(group.tracks.map(\.path))
        let allSelected = paths.isSubset(of: selection)
        return HStack(spacing: 10) {
            ArtworkView(artworkId: group.artworkId, pixelSize: 96, cornerRadius: 4)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textPrimary)
                Text([group.subtitle, "\(group.tracks.count) song\(group.tracks.count == 1 ? "" : "s")"]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(theme.textSecondary)
            }
            .lineLimit(1)
            Spacer()
            Button(allSelected ? "Deselect" : "Select") {
                if allSelected { selection.subtract(paths) } else { selection.formUnion(paths) }
            }
            .controlSize(.small)
            Button("Edit in TagBee") { send(group.tracks) }
                .controlSize(.small)
                .disabled(!hasEditor)
        }
        .padding(.vertical, 4)
    }

    /// The name of the playlist (or smart playlist) clicked in the sidebar, if any.
    private var sourceName: String? {
        if missingArtwork {
            let albums = Set(results.map(\.albumKey)).count
            return "Songs without artwork: \(results.count) in \(albums) album\(albums == 1 ? "" : "s")"
        }
        if dropped != nil { return "Songs dragged here" }
        guard let id = app.trackStudioSourcePlaylistId else { return nil }
        if let smart = SmartPlaylist(playlistId: id) { return smart.title }
        return app.playlists?.playlist(id: id)?.name
    }

    private var hasEditor: Bool { preferences.tagEditorPath != nil }

    private func showMissingArtwork() {
        dropped = nil
        app.trackStudioSourcePlaylistId = nil
        query = ""
        selection = []
        missingArtwork = true
    }

    /// Empties the list: dragged songs, the playlist shown, and the search.
    private func clearList() {
        dropped = nil
        missingArtwork = false
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
