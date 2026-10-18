import MacBeeLibrary
import SwiftUI

/// One album: big cover, title, artist, Shuffle / Play, the labeled actions
/// (Play Next, Add to Queue, Add to Playlist, Favorite), and the track list.
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
        .overlay(alignment: .topLeading) {
            if app.canGoBack {
                CircleButton(systemImage: "chevron.left", help: "Back", tinted: false) { app.goBack() }
                    .padding(.leading, 20)
                    .padding(.top, 14)
            }
        }
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
    /// The album's songs, for the + menu.
    let tracks: [Track]
    let onArtist: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ArtworkView(artworkId: album.artworkId, pixelSize: 800, cornerRadius: 8)
                .frame(width: 260, height: 260)
                .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(album.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                Button(action: onArtist) {
                    Text(album.artist)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Go to \(album.artist)")
                Text(details)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 2)
                HStack(spacing: 12) {
                    CircleButton(systemImage: "shuffle", help: "Shuffle", diameter: 40, action: onShuffle)
                    PlayCapsuleButton(action: onPlay)
                }
                .padding(.top, 14)
                AlbumActions(tracks: tracks)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 56) // room for the back button
        .padding([.horizontal, .bottom], 16)
        .background {
            // The album's colors, softly blurred, like the artist and playlist pages.
            ArtworkView(artworkId: album.artworkId, pixelSize: 300, cornerRadius: 0)
                .blur(radius: 50)
                .saturation(1.2)
                .overlay(theme.background.opacity(0.4))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

private struct PlayCapsuleButton: View {
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label("Play", systemImage: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 34)
                .frame(height: 40)
                .background(Capsule().fill(hovering ? theme.elevated : theme.surface))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Play")
    }
}

/// Play Next, Add to Queue, Add to Playlist and Favorite, as small labeled buttons under Play.
private struct AlbumActions: View {
    let tracks: [Track]
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        HStack(spacing: 8) {
            ActionPill(title: "Play Next", systemImage: "text.line.first.and.arrowtriangle.forward",
                       help: "Play these songs right after the current one") { player.playNext(tracks) }
            ActionPill(title: "Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward",
                       help: "Add these songs to the end of Up Next") { player.addToQueue(tracks) }
            Menu {
                AddToPlaylistItems { tracks }
            } label: {
                ActionPillLabel(title: "Add to Playlist", systemImage: "text.badge.plus")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add this album to a playlist")
            ActionPill(title: isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart",
                       help: isFavorite ? "Remove from Favorites" : "Add to Favorites (shows in Collection)") {
                player.setFavorite(tracks, !isFavorite)
            }
        }
        .disabled(tracks.isEmpty)
    }

    /// The album counts as a favorite when every song on it is one.
    private var isFavorite: Bool {
        !tracks.isEmpty && tracks.allSatisfy { player.isFavorite($0) }
    }
}

private struct ActionPill: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionPillLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Icon and text in a rounded pill, brighter while hovered.
private struct ActionPillLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(hovering ? theme.elevated : theme.surface))
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}
