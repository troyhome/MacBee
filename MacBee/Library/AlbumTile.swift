import MacBeeLibrary
import SwiftUI

struct AlbumTile: View {
    let album: AlbumSummary
    var showsArtist = true
    let onPlay: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(artworkId: album.artworkId, pixelSize: 420)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: hovering ? 10 : 0, y: hovering ? 4 : 0)
                .overlay(alignment: .bottomTrailing) {
                    if hovering { HoverPlayButton(action: onPlay) }
                }
            Text(album.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .draggable(DragPayload.album(album.albumKey).string) // drop on a playlist to add the album
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering } }
        .help("\(album.title) — \(album.artist)")
    }

    private var subtitle: String {
        if showsArtist { return album.artist }
        return [album.year.map(String.init), Format.quality(bitDepth: album.maxBitDepth, sampleRate: album.maxSampleRate)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
