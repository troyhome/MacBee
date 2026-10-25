import MacBeeLibrary
import SwiftUI

/// One album: big cover, title, artist, Shuffle / Play, the labeled actions
/// (a heart, and a "…" menu with Play Next, Add to Queue, Add to Playlist, Edit in TagBee, Show in Finder), and the track list.
/// Double-click a track to play from there. The back button returns to where you came from.
struct AlbumDetailView: View {
    let album: AlbumSummary

    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @AppStorage("selectedArtist") private var selectedArtistKey = ""
    @State private var model = AlbumDetailViewModel()
    @State private var selection = Set<String>()

    var body: some View {
        ScrollViewReader { proxy in
        List(selection: $selection) {
            AlbumHeader(album: album,
                        genre: model.genre,
                        onShuffle: { player.playShuffled(model.tracks) },
                        onPlay: { player.play(model.tracks) },
                        tracks: model.tracks,
                        onArtist: openArtist)
                .padding(.bottom, 16)
                .listRowSeparator(.hidden)
            ForEach(model.tracks, id: \.path) { track in
                TrackRow(track: track,
                         showsDisc: model.hasMultipleDiscs,
                         showsArtist: model.showsTrackArtists,
                         isCurrent: player.currentTrack?.path == track.path,
                         isPlaying: player.isPlaying,
                         isFavorite: player.isFavorite(track))
                    .tag(track.path)
                    .id(track.path)
                        .draggable(dragPayload(for: track, in: model.tracks))
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
        .background(theme.background)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(album.title)
        .task(id: "\(album.albumKey)-\(library.revision)") {
            await model.load(albumKey: album.albumKey, from: library.database)
            // Opened from the play bar: bring the playing song into view.
            if let current = player.currentTrack?.path, model.tracks.contains(where: { $0.path == current }) {
                proxy.scrollTo(current, anchor: .center)
            }
        }
        }
    }

    private func play(_ path: String?) {
        guard let path, let index = model.tracks.firstIndex(where: { $0.path == path }) else { return }
        player.play(model.tracks, startAt: index)
    }

    private func openArtist() {
        selectedArtistKey = album.artistKey
        app.go(to: .artists)
    }

    /// Dragging a selected song carries every selected song; otherwise just that one.
    private func dragPayload(for track: Track, in tracks: [Track]) -> String {
        let chosen = selection.contains(track.path) ? tracks.filter { selection.contains($0.path) } : [track]
        return DragPayload.tracks(chosen.compactMap(\.id)).string
    }
}

private struct AlbumHeader: View {
    let album: AlbumSummary
    let genre: String?
    let onShuffle: () -> Void
    let onPlay: () -> Void
    /// The album's songs, for the heart and the "…" menu.
    let tracks: [Track]
    let onArtist: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        DetailHero(label: "Album", title: album.title) {
            ArtworkView(artworkId: album.artworkId, pixelSize: 800, cornerRadius: 8)
        } subtitle: {
            HStack(spacing: 0) {
                Button(action: onArtist) {
                    Text(album.artist).fontWeight(.semibold).foregroundStyle(theme.textPrimary)
                }
                .buttonStyle(.plain)
                .help("Go to \(album.artist)")
                Text(" · " + details)
            }
            .lineLimit(1)
        } controls: {
            PlayControls(onPlay: onPlay, onShuffle: onShuffle, favoriteTracks: tracks) {
                AlbumActionsMenu(tracks: tracks, onArtist: onArtist)
            }
            .disabled(tracks.isEmpty)
        } backdrop: {
            ArtworkView(artworkId: album.artworkId, pixelSize: 300, cornerRadius: 0)
        }
        .padding([.horizontal, .bottom], 4)
    }

    /// e.g. "Alternative · 1999 · 16/44.1 · 9 songs, 1 hr 12 min"
    private var details: String {
        var quality = Format.quality(bitDepth: album.maxBitDepth, sampleRate: album.maxSampleRate)
        if (album.maxBitDepth ?? 0) >= 24 && (album.maxSampleRate ?? 0) >= 88_200, let q = quality {
            quality = "Hi-Res \(q)"
        }
        let songs = "\(album.trackCount) \(album.trackCount == 1 ? "song" : "songs"), \(Format.minutes(album.duration))"
        return [genre, album.year.map(String.init), quality, songs].compactMap { $0 }.joined(separator: " · ")
    }
}
