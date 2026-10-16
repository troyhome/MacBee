import MacBeeLibrary
import SwiftUI

/// Right column of the Artists page: header, then every album with its songs.
/// Double-click a song to play its album from there; click an album title to open it.
struct ArtistPageView: View {
    let artist: ArtistSummary

    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation
    @Environment(\.theme) private var theme
    @State private var model = ArtistPageViewModel()
    @State private var selection = Set<String>()

    var body: some View {
        List(selection: $selection) {
            ArtistPageHeader(artist: artist,
                             onPlay: { player.play(model.allTracks) },
                             onShuffle: { player.playShuffled(model.allTracks) })
                .listRowSeparator(.hidden)
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

private struct ArtistPageHeader: View {
    let artist: ArtistSummary
    let onPlay: () -> Void
    let onShuffle: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(artist.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                CircleButton(systemImage: "play.fill", help: "Play", action: onPlay)
                CircleButton(systemImage: "shuffle", help: "Shuffle", action: onShuffle)
            }
            Text("\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums"), \(artist.trackCount) \(artist.trackCount == 1 ? "song" : "songs")")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            Rectangle().fill(theme.separator).frame(height: 1).padding(.top, 6)
        }
        .padding(.top, 18)
    }
}

private struct ArtistAlbumHeader: View {
    let section: ArtistPageViewModel.AlbumSection
    let onOpen: () -> Void
    let onPlay: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            Button(action: onOpen) {
                ArtworkView(artworkId: section.album.artworkId, pixelSize: 400)
                    .frame(width: 150, height: 150)
            }
            .buttonStyle(.plain)
            .help("Open album")
            VStack(alignment: .leading, spacing: 5) {
                Button(action: onOpen) {
                    Text(section.album.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .help("Open album")
                Text(details)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            CircleButton(systemImage: "play.fill", help: "Play album", action: onPlay)
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
