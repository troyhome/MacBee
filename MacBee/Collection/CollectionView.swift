import MacBeeLibrary
import SwiftUI

/// The Collections page: your playlists, compilation albums (Various Artists), saved mixes, and the albums,
/// songs and videos you've liked, with tabs along the top.
struct CollectionView: View {
    @Environment(AppModel.self) private var app
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
        .navigationTitle("Collections")
        .task(id: "\(library.revision)-\(player.favoritesSaved)") {
            await model.load(from: library.database)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if app.canGoBack {
                    CircleButton(systemImage: "chevron.left", help: "Back", tinted: false) { app.goBack() }
                }
                Text("Collections")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
            }
            CollectionTabs(section: $section)
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
        case .variousArtists:
            AlbumGrid(albums: model.compilations, indexName: { $0.title })
                .overlay {
                    if model.isLoaded && model.compilations.isEmpty {
                        ContentUnavailableView("No compilations", systemImage: "person.3",
                                               description: Text("Albums by various artists show up here."))
                    }
                }
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
            VideosView(embedded: true)
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
