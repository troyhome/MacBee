import MacBeeLibrary
import SwiftUI

/// Small format label, e.g. "FLAC 16/44.1". Hi-res files (24-bit at 88.2 kHz or more, or DSD) use the accent color.
struct QualityBadge: View {
    let track: Track
    @Environment(\.theme) private var theme
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        if preferences.showQualityBadges { badge }
    }

    private var badge: some View {
        let color = isHiRes ? theme.accent : theme.textTertiary
        return Text(isHiRes ? "HI-RES  \(track.formatSummary)" : track.formatSummary)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.7), lineWidth: 1))
            .fixedSize()
    }

    private var isHiRes: Bool {
        track.codec == "DSD" || ((track.bitDepth ?? 0) >= 24 && (track.sampleRate ?? 0) >= 88_200)
    }
}
