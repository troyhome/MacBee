import MacBeeLibrary
import SwiftUI

/// Plays grouped by day (Today, Yesterday, dates), newest first. Double-click a row to play that song.
struct PlayHistoryList: View {
    let days: [PlayHistoryDay]
    let canLoadMore: Bool
    let onLoadMore: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(days) { day in
                Text(day.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                ForEach(day.entries) { entry in
                    PlayHistoryRow(entry: entry)
                }
            }
            if canLoadMore {
                Button("Show More", action: onLoadMore)
                    .buttonStyle(.link)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct PlayHistoryRow: View {
    let entry: PlayHistoryEntry
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(Format.clockTime(entry.playedAt))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
                .frame(width: 64, alignment: .leading)
            ArtworkView(artworkId: entry.track.artworkId, pixelSize: 100, cornerRadius: 4)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.track.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                Text("\(entry.track.displayArtist) — \(entry.track.displayAlbum)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
            .lineLimit(1)
            Spacer()
            Text(Format.time(entry.track.duration))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? theme.surface : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { player.play([entry.track]) }
        .contextMenu {
            TrackContextMenu(tracks: [entry.track]) { player.play([entry.track]) }
        }
    }
}
