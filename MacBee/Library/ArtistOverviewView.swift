import MacBeeLibrary
import MacBeeVideo
import SwiftUI

/// The TIDAL-style artist page: rows of Albums (covers only), EPs & Singles, Mixes, Videos (music videos
/// with the artist's name) and Similar Artists (others in the library with the same genres).
struct ArtistOverviewView: View {
    let artist: ArtistSummary
    @Binding var layout: ArtistLayout
    let onSelectArtist: (ArtistSummary) -> Void

    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation
    @Environment(\.theme) private var theme
    @State private var model = ArtistOverviewViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Stays put while the rows scroll.
            ArtistPageHeader(artist: artist, layout: $layout,
                             onPlay: { player.play(model.allTracks) },
                             onShuffle: { player.playShuffled(model.allTracks) })
            rows
        }
        .task(id: "\(artist.artistKey)-\(library.revision)") {
            await model.load(artist: artist, from: library.database)
        }
    }

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Color.clear.frame(height: 0)
                if !model.albums.isEmpty {
                    row("Albums") { albumRow(model.albums) }
                }
                if !model.epsAndSingles.isEmpty {
                    row("EPs & Singles") { albumRow(model.epsAndSingles) }
                }
                if !model.mixes.isEmpty {
                    row("Mixes") { MixRow(mixes: model.mixes) }
                }
                if !videos.isEmpty {
                    row("Videos") { videoRow }
                }
                if !model.similar.isEmpty {
                    row("Similar Artists") { similarRow }
                }
            }
            .padding(.bottom, 30)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.mbSection)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)
            content()
        }
    }

    private func albumRow(_ albums: [AlbumSummary]) -> some View {
        HorizontalCarousel {
            LazyHStack(alignment: .top, spacing: 18) {
                ForEach(albums) { album in
                    VStack(alignment: .leading, spacing: 0) {
                        AlbumTile(album: album, showsArtist: false) { Task { await player.playAlbum(album) } }
                            .onTapGesture { navigation.openAlbum(album) }
                            .contextMenu { AlbumContextMenu(album: album) }
                        Text([album.year.map(String.init), ArtistOverviewViewModel.kind(album)].compactMap { $0 }
                            .joined(separator: " · "))
                            .font(.mbCaption)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .frame(width: 160)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    /// Music videos whose title or folder has the artist's name.
    private var videos: [MusicVideo] {
        app.videos.catalog.musicVideos.filter {
            $0.title.localizedCaseInsensitiveContains(artist.name) || $0.folderName.localizedCaseInsensitiveContains(artist.name)
        }
    }

    private var videoRow: some View {
        HorizontalCarousel {
            HStack(alignment: .top, spacing: 18) {
                ForEach(videos) { video in
                    VideoPosterCard(title: .musicVideo(video)) { app.playMusicVideo(video) }
                        .frame(width: 150)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    private var similarRow: some View {
        HorizontalCarousel {
            HStack(alignment: .top, spacing: 22) {
                ForEach(model.similar) { other in
                    Button { onSelectArtist(other) } label: {
                        VStack(spacing: 8) {
                            ArtworkView(artworkId: other.artworkId, pixelSize: 360, cornerRadius: 70)
                                .frame(width: 140, height: 140)
                            Text(other.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                                .frame(width: 150)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Go to \(other.name)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }
}
