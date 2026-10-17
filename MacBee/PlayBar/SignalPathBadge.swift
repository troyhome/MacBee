import MacBeeAudio
import SwiftUI

/// "Bit-perfect" badge plus the track's format (and bitrate for MP3/AAC). The only place the play bar
/// shows the format. Hover for the details.
struct SignalPathBadge: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            PlexSourceTag()
            badge
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let status = player.engine.signalPath, let format = player.engine.currentFormat {
            let color = status.isBitPerfect ? theme.good : theme.warning
            VStack(alignment: .trailing, spacing: 3) {
                Text(status.isBitPerfect ? "BIT-PERFECT" : "NOT BIT-PERFECT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1))
                Text(formatLine(format))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
            }
            .help(tooltip(status))
        }
    }

    /// e.g. "FLAC 24-bit / 96 kHz", or "MP3 44.1 kHz · 320 kbps" for lossy files.
    private func formatLine(_ format: AudioFormatInfo) -> String {
        guard format.codec == .mp3 || format.codec == .aac,
              let kbps = player.currentTrack?.bitrate, kbps > 0 else { return format.displayString }
        return "\(format.displayString) · \(Int(kbps.rounded())) kbps"
    }

    private func tooltip(_ status: SignalPathStatus) -> String {
        var lines = status.summaryLines
        lines.append("Output: \(player.engine.outputDevice?.name ?? "none")")
        if let error = player.engine.lastError { lines.append("Last problem: \(error)") }
        return lines.joined(separator: "\n")
    }
}

/// "PLEX" when the song comes from Plex; "Getting from Plex…" while a song downloads. No animation.
private struct PlexSourceTag: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        if let fetching = player.router.fetchingTitle {
            Text("Getting from Plex…")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .help("Fetching “\(fetching)” from your Plex server")
        } else if player.isPlayingFromPlex {
            Text("PLEX")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color(hex: 0xE5A00D))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(Capsule().stroke(Color(hex: 0xE5A00D).opacity(0.8), lineWidth: 1))
                .help("Playing the original file from your Plex server (the network drive isn't reachable or Plex is chosen in Preferences)")
        }
    }
}
