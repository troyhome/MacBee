import MacBeeLibrary
import SwiftUI

/// Search page: matching artists, albums and songs.
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation
    @Environment(\.theme) private var theme
    @AppStorage("selectedArtist") private var selectedArtistKey = ""
    @State private var model = SearchViewModel()
    @State private var selection = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Search", subtitle: model.searchedText.isEmpty ? nil : "Results for “\(model.searchedText)”")
            results
        }
    }

    private var results: some View {
        List(selection: $selection) {
            if !model.artists.isEmpty {
                sectionTitle("Artists")
                HorizontalCarousel {
                    HStack(spacing: 18) {
                        ForEach(model.artists) { artist in
                            SearchArtistCard(artist: artist)
                                .onTapGesture(count: 2) { Task { await player.playArtist(artist) } }
                                .onTapGesture { openArtist(artist) }
                                .contextMenu { ArtistContextMenu(artist: artist) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowSeparator(.hidden)
            }
            if !model.albums.isEmpty {
                sectionTitle("Albums")
                HorizontalCarousel {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(model.albums) { album in
                            AlbumTile(album: album) { Task { await player.playAlbum(album) } }
                                .frame(width: 150)
                                // Click or double-click opens the album; only the hover play button starts it.
                                .onTapGesture { navigation.openAlbum(album) }
                                .contextMenu { AlbumContextMenu(album: album) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowSeparator(.hidden)
            }
            if !model.tracks.isEmpty {
                sectionTitle("Songs")
                ForEach(model.tracks, id: \.path) { track in
                    TrackRow(track: track,
                             showsArtist: true,
                             isCurrent: player.currentTrack?.path == track.path,
                             isPlaying: player.isPlaying,
                             isFavorite: player.isFavorite(track))
                        .tag(track.path)
                        .draggable(dragPayload(for: track, in: model.tracks))
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { paths in
            TrackContextMenu(tracks: model.tracks.filter { paths.contains($0.path) }) {
                play(model.tracks.first { paths.contains($0.path) }?.path)
            }
        } primaryAction: { paths in
            play(paths.first)
        }
        .scrollContentBackground(.hidden)
        // Keeps the first row (the top artist) clear of the toolbar.
        .contentMargins(.top, 16, for: .scrollContent)
        .overlay { emptyState }
        .navigationTitle("Search")
        .task(id: "\(app.searchText)-\(library.revision)") {
            try? await Task.sleep(for: .milliseconds(200)) // wait for typing to pause
            guard !Task.isCancelled else { return }
            selection = []
            await model.search(app.searchText, in: library.database, revision: library.revision)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if app.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("Search your library", systemImage: "magnifyingglass",
                                   description: Text("Type an artist, album or song in the box at the top of the sidebar."))
        } else if model.isEmpty && model.searchedText == app.searchText.trimmingCharacters(in: .whitespacesAndNewlines) {
            ContentUnavailableView.search(text: model.searchedText)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.mbSection)
            .foregroundStyle(theme.textPrimary)
            .padding(.top, 14)
            .listRowSeparator(.hidden)
    }

    /// Plays the songs list from the chosen song.
    private func play(_ path: String?) {
        guard let path, let index = model.tracks.firstIndex(where: { $0.path == path }) else { return }
        player.play(model.tracks, startAt: index)
    }

    private func openArtist(_ artist: ArtistSummary) {
        selectedArtistKey = artist.artistKey
        app.go(to: .artists)
    }

    /// Dragging a selected song carries every selected song; otherwise just that one.
    private func dragPayload(for track: Track, in tracks: [Track]) -> String {
        let chosen = selection.contains(track.path) ? tracks.filter { selection.contains($0.path) } : [track]
        return DragPayload.tracks(chosen.compactMap(\.id)).string
    }
}

private struct SearchArtistCard: View {
    let artist: ArtistSummary
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            ArtworkView(artworkId: artist.artworkId, pixelSize: 240, cornerRadius: 50)
                .frame(width: 100, height: 100)
            Text(artist.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .frame(width: 110)
        }
        .contentShape(Rectangle())
        .help("Click to open, double-click to play")
    }
}
