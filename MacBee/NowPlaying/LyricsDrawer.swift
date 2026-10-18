import MacBeeLibrary
import SwiftUI

/// Slides in from the right (where the queue goes): the playing song's lyrics, following the music.
struct LyricsDrawer: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lyrics")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                BarIconButton(systemImage: "xmark", help: "Close lyrics", size: 12) { app.showLyrics = false }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            if let track = player.currentTrack {
                Text("\(track.displayTitle) · \(track.displayArtist)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                LyricsPanel(track: track)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Text("Nothing is playing.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .padding(16)
                Spacer()
            }
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .leading) { Rectangle().fill(theme.separator).frame(width: 1) }
        .shadow(color: .black.opacity(0.35), radius: 16, x: -4)
    }
}
