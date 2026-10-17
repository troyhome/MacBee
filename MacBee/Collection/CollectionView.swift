import MacBeeLibrary
import SwiftUI

/// The Collection page: your playlists plus the albums and songs you've hearted, with tabs along the top.
struct CollectionView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @AppStorage("collectionSection") private var section: CollectionSection = .playlists
    @State private var model = CollectionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Collection")
        .task(id: "\(library.revision)-\(player.favoritesSaved)") {
            await model.load(from: library.database)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Collection")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Picker("Show", selection: $section) {
                ForEach(CollectionSection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .playlists:
            AllPlaylistsView(embedded: true)
        case .albums:
            AlbumGrid(albums: model.albums)
                .overlay {
                    if model.isLoaded && model.albums.isEmpty {
                        ContentUnavailableView("No favorite albums yet", systemImage: "heart",
                                               description: Text(model.errorMessage ?? "Open an album and click the heart next to Play."))
                    }
                }
        case .tracks:
            CollectionTrackList(tracks: model.tracks)
                .overlay {
                    if model.isLoaded && model.tracks.isEmpty {
                        ContentUnavailableView("No favorite songs yet", systemImage: "heart",
                                               description: Text(model.errorMessage ?? "Click the heart in the play bar, or right-click songs to favorite them."))
                    }
                }
        case .videos:
            ContentUnavailableView("No videos", systemImage: "play.rectangle",
                                   description: Text("MacBee plays music only for now. Music videos may come later."))
        case .savedMixes:
            ContentUnavailableView("No saved mixes yet", systemImage: "square.stack.3d.up",
                                   description: Text("Saving suggested mixes from the Music page comes in a later update."))
        }
    }
}

/// Favorite songs. Double-click plays from that song; right-click for the usual song menu.
private struct CollectionTrackList: View {
    let tracks: [Track]
    @Environment(PlayerViewModel.self) private var player
    @State private var selection = Set<String>()

    var body: some View {
        List(selection: $selection) {
            ForEach(tracks, id: \.path) { track in
                TrackRow(track: track,
                         showsArtist: true,
                         isCurrent: player.currentTrack?.path == track.path,
                         isPlaying: player.isPlaying,
                         isFavorite: player.isFavorite(track))
                    .tag(track.path)
                    .draggable(dragPayload(for: track))
            }
        }
        .contextMenu(forSelectionType: String.self) { paths in
            TrackContextMenu(tracks: tracks.filter { paths.contains($0.path) }) {
                play(tracks.first { paths.contains($0.path) }?.path)
            }
        } primaryAction: { paths in
            play(paths.first)
        }
        .scrollContentBackground(.hidden)
    }

    private func play(_ path: String?) {
        guard let path, let index = tracks.firstIndex(where: { $0.path == path }) else { return }
        player.play(tracks, startAt: index)
    }

    /// Dragging a selected song carries every selected song; otherwise just that one.
    private func dragPayload(for track: Track) -> String {
        let chosen = selection.contains(track.path) ? tracks.filter { selection.contains($0.path) } : [track]
        return DragPayload.tracks(chosen.compactMap(\.id)).string
    }
}
