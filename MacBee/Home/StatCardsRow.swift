import MacBeeLibrary
import SwiftUI

/// Artists, Albums, Tracks, Total time.
struct StatCardsRow: View {
    let stats: LibraryStats

    var body: some View {
        HStack(spacing: 14) {
            StatCard(label: "Artists", value: stats.artists.formatted())
            StatCard(label: "Albums", value: stats.albums.formatted())
            StatCard(label: "Tracks", value: stats.tracks.formatted())
            StatCard(label: "Total time", value: Format.longDuration(stats.totalDuration))
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: 190, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }
}
