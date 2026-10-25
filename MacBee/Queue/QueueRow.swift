import MacBeeLibrary
import SwiftUI

/// A song in the queue drawer. Up Next rows show an x on hover to remove them.
struct QueueRow: View {
    let track: Track
    var isCurrent = false
    var isPlaying = false
    var onRemove: (() -> Void)?

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(artworkId: track.artworkId, pixelSize: 100, cornerRadius: 4)
                .frame(width: 36, height: 36)
                .overlay {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .font(.mbSecondary)
                            .foregroundStyle(theme.accent)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(track.displayTitle)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? theme.accent : theme.textPrimary)
                Text(track.displayArtist)
                    .font(.mbCaption)
                    .foregroundStyle(theme.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            if hovering, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from queue")
            } else {
                Text(Format.time(track.duration))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
