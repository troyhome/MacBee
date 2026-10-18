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
                PillTabs(items: TagsSection.allCases, selection: $section, title: \.title, systemImage: \.systemImage)
                Spacer()
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
        .navigationTitle("Track Studio")
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
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                FilterField(prompt: "Find songs, albums or artists to tag", text: $query)
                    .frame(maxWidth: 360)
                Button("Select All") { selection = Set(results.map(\.path)) }
                    .disabled(results.isEmpty)
                Button("Open \(selection.count) in TagBee") { send(results.filter { selection.contains($0.path) }) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty || !hasEditor)
                Spacer()
                Menu("Send to TagBee") {
                    Button("The Song Playing") { if let track = player.currentTrack { send([track]) } }
                        .disabled(player.currentTrack == nil)
                    Button("The Album Playing") { Task { await sendPlayingAlbum() } }
                        .disabled(player.currentTrack == nil)
                    Divider()
                    Button("Just Open TagBee") {
                        if let path = preferences.tagEditorPath { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    }
                }
                .fixedSize()
                .disabled(!hasEditor)
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
                if results.isEmpty {
                    ContentUnavailableView("Find songs to tag", systemImage: "tag",
                                           description: Text(hasEditor
                                               ? "Search above, tick songs (⌘-click or ⇧-click for several) and open them in TagBee. Double-click opens one. Changes saved in TagBee show up here by themselves."
                                               : "TagBee isn't installed. Choose a tag editor in Settings > Tag Editor."))
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let text = query.trimmingCharacters(in: .whitespaces)
            results = text.isEmpty ? [] : ((try? await library.database.search(text, limit: 500)) ?? [])
            selection = selection.intersection(results.map(\.path))
        }
    }

    private var hasEditor: Bool { preferences.tagEditorPath != nil }

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
