import MacBeeLibrary
import SwiftUI

/// Right column of the Artists page. Two layouts, switched in the header: every album with its songs
/// (double-click a song to play its album from there; click an album title to open it), or the TIDAL-style
/// overview (`ArtistOverviewView`).
struct ArtistPageView: View {
    let artist: ArtistSummary
    /// Opens another artist (from Similar Artists).
    var onSelectArtist: (ArtistSummary) -> Void = { _ in }
    @AppStorage("artistLayout") private var layout: ArtistLayout = .albumsWithSongs

    var body: some View {
        if layout == .overview {
            ArtistOverviewView(artist: artist, layout: $layout, onSelectArtist: onSelectArtist)
        } else {
            ArtistAlbumsWithSongsView(artist: artist, layout: $layout)
        }
    }
}

/// Every album of the artist, each with its songs.
private struct ArtistAlbumsWithSongsView: View {
    let artist: ArtistSummary
    @Binding var layout: ArtistLayout

    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation
    @Environment(\.theme) private var theme
    @State private var model = ArtistPageViewModel()
    @State private var selection = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            // Stays put while the albums scroll.
            ArtistPageHeader(artist: artist, layout: $layout,
                             onPlay: { player.play(model.allTracks) },
                             onShuffle: { player.playShuffled(model.allTracks) })
            albumList
        }
    }

    private var albumList: some View {
        List(selection: $selection) {
            ForEach(model.sections) { section in
                ArtistAlbumHeader(section: section,
                                  onOpen: { navigation.openAlbum(section.album) },
                                  onPlay: { player.play(section.tracks) })
                    .padding(.top, 22)
                    .padding(.bottom, 6)
                    .listRowSeparator(.hidden)
                ForEach(section.tracks, id: \.path) { track in
                    TrackRow(track: track,
                             showsDisc: section.hasMultipleDiscs,
                             showsArtist: section.showsTrackArtists,
                             isCurrent: player.currentTrack?.path == track.path,
                             isPlaying: player.isPlaying,
                             isFavorite: player.isFavorite(track))
                        .tag(track.path)
                        .draggable(dragPayload(for: track, in: model.allTracks))
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { paths in
            TrackContextMenu(tracks: model.allTracks.filter { paths.contains($0.path) }) {
                play(model.allTracks.first { paths.contains($0.path) }?.path)
            }
        } primaryAction: { paths in
            play(paths.first)
        }
        .scrollContentBackground(.hidden)
        .task(id: "\(artist.artistKey)-\(library.revision)") {
            selection = []
            await model.load(artistKey: artist.artistKey, from: library.database)
        }
    }

    private func play(_ path: String?) {
        for section in model.sections {
            if let index = section.tracks.firstIndex(where: { $0.path == path }) {
                player.play(section.tracks, startAt: index)
                return
            }
        }
    }

    /// Dragging a selected song carries every selected song; otherwise just that one.
    private func dragPayload(for track: Track, in tracks: [Track]) -> String {
        let chosen = selection.contains(track.path) ? tracks.filter { selection.contains($0.path) } : [track]
        return DragPayload.tracks(chosen.compactMap(\.id)).string
    }
}

struct ArtistPageHeader: View {
    let artist: ArtistSummary
    @Binding var layout: ArtistLayout
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        PageHeader(title: artist.name, subtitle: counts, showsDivider: true) {
            PlayControls(onPlay: onPlay, onShuffle: onShuffle, large: false) {
                ArtistContextMenu(artist: artist, showsGoTo: false)
            }
            HeaderDivider()
            Picker("Layout", selection: $layout) {
                ForEach(ArtistLayout.allCases) { Image(systemName: $0.systemImage).help($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show albums with their songs, or a TIDAL-style overview")
        }
    }

    private var counts: String {
        "\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums") · \(artist.trackCount) \(artist.trackCount == 1 ? "song" : "songs")"
    }
}

private struct ArtistAlbumHeader: View {
    let section: ArtistPageViewModel.AlbumSection
    let onOpen: () -> Void
    let onPlay: () -> Void
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var hoveringArtwork = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            Button(action: onOpen) {
                ArtworkView(artworkId: section.album.artworkId, pixelSize: 400)
                    .frame(width: 150, height: 150)
            }
            .buttonStyle(.plain)
            .help("Open album")
            // Play appears on the artwork under the mouse, like the album grid.
            .overlay(alignment: .bottomTrailing) {
                if hoveringArtwork { HoverPlayButton(action: onPlay, help: "Play album") }
            }
            .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hoveringArtwork = isHovering } }
            VStack(alignment: .leading, spacing: 5) {
                Button(action: onOpen) {
                    Text(section.album.title)
                        .font(.mbSection)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .help("Open album")
                Text(details)
                    .font(.mbSecondary)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            FavoriteTracksButton(tracks: section.tracks, diameter: 34)
            AlbumMoreMenu(tracks: section.tracks)
        }
        .padding(14)
        .background {
            // The album's colors, softly blurred, like the Now Playing background.
            ArtworkView(artworkId: section.album.artworkId, pixelSize: 300, cornerRadius: 0)
                .blur(radius: 45)
                .saturation(1.2)
                .overlay(theme.background.opacity(0.4))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var details: String {
        [section.genre,
         section.album.year.map(String.init),
         Format.quality(bitDepth: section.album.maxBitDepth, sampleRate: section.album.maxSampleRate)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
