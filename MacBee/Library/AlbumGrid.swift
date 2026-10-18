import MacBeeLibrary
import SwiftUI

/// Albums as a cover grid or a list with round covers. Clicking opens the album; the play button on hover plays it.
/// With `indexName`, an A–Z strip on the right jumps to the first album under each letter.
struct AlbumGrid: View {
    let albums: [AlbumSummary]
    var showsArtist = true
    var layout: AlbumLayout = .grid
    /// The name the A–Z strip goes by (artist or title, matching the sort). Nil hides the strip.
    var indexName: ((AlbumSummary) -> String)?

    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation

    private let columns = [GridItem(.adaptive(minimum: Metrics.albumTileMin, maximum: Metrics.albumTileMax),
                                    spacing: 20, alignment: .top)]

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                ScrollView {
                    Group {
                        if layout == .grid {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                                ForEach(albums) { album in
                                    AlbumTile(album: album, showsArtist: showsArtist) { play(album) }
                                        .id(album.albumKey)
                                        // Click or double-click opens the album; only the hover play button starts it.
                                        .onTapGesture { navigation.openAlbum(album) }
                                        .contextMenu { AlbumContextMenu(album: album) }
                                }
                            }
                        } else {
                            LazyVStack(spacing: 2) {
                                ForEach(albums) { album in
                                    AlbumListRow(album: album, showsArtist: showsArtist) { play(album) }
                                        .id(album.albumKey)
                                        .onTapGesture { navigation.openAlbum(album) }
                                        .contextMenu { AlbumContextMenu(album: album) }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                // The A–Z strip sits beside the albums, clear of the scroll bar.
                if let indexName {
                    AlphabetIndex(available: Set(albums.map { AlphabetIndex.letter(for: indexName($0)) })) { letter in
                            if let first = albums.first(where: { AlphabetIndex.letter(for: indexName($0)) == letter }) {
                                proxy.scrollTo(first.albumKey, anchor: .top)
                            }
                        }
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func play(_ album: AlbumSummary) {
        Task { await player.playAlbum(album) }
    }
}

/// One album in the list layout: round cover, title, artist, year and song count.
private struct AlbumListRow: View {
    let album: AlbumSummary
    let showsArtist: Bool
    let onPlay: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(artworkId: album.artworkId, pixelSize: 120, cornerRadius: 26)
                .frame(width: 52, height: 52)
                .overlay {
                    if hovering {
                        Button(action: onPlay) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.onAccent)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(theme.accent))
                        }
                        .buttonStyle(.plain)
                        .help("Play")
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                if showsArtist {
                    Text(album.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            Text(details)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? theme.surface : .clear))
        .contentShape(Rectangle())
        .draggable(DragPayload.album(album.albumKey).string)
        .onHover { hovering = $0 }
        .help("\(album.title) — \(album.artist)")
    }

    private var details: String {
        let songs = "\(album.trackCount) \(album.trackCount == 1 ? "song" : "songs")"
        return [album.year.map(String.init), songs].compactMap { $0 }.joined(separator: " · ")
    }
}
