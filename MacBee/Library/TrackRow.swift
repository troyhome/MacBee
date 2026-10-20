import MacBeeLibrary
import SwiftUI

struct TrackRow: View {
    let track: Track
    var showsDisc = false
    var showsArtist = false
    var isCurrent = false
    var isPlaying = false
    var isFavorite = false
    /// A small cover before the title (Track Studio).
    var showsArtwork = false

    @Environment(\.theme) private var theme
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(theme.accent)
                } else {
                    Text(number)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .font(.system(size: 12).monospacedDigit())
            .frame(width: 34, alignment: .trailing)

            if showsArtwork {
                ArtworkView(artworkId: track.artworkId, pixelSize: 72, cornerRadius: 3)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(track.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(isCurrent ? theme.accent : theme.textPrimary)
                if showsArtist {
                    Text(track.displayArtist)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .lineLimit(1)

            Spacer(minLength: 12)

            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.accent)
            }
            if preferences.showQualityBadges {
                Text(track.formatSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            Text(Format.time(track.duration))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var number: String {
        guard let n = track.trackNumber else { return "–" }
        if showsDisc, let disc = track.discNumber { return "\(disc)-\(n)" }
        return "\(n)"
    }
}
