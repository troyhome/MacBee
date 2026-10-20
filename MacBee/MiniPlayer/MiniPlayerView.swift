import MacBeeLibrary
import SwiftUI

/// Small floating player. Closing it (or the expand button) brings back the main window.
struct MiniPlayerView: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    /// Stay above other windows.
    @AppStorage("miniPlayerOnTop") private var onTop = true

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(artworkId: player.currentTrack?.artworkId, pixelSize: 200, cornerRadius: 6)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.displayTitle ?? "Not playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(player.currentTrack?.displayArtist ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
                .lineLimit(1)
                .help(player.currentTrack.map { "\($0.displayTitle)\n\($0.displayArtist)" } ?? "")
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    BarIconButton(systemImage: onTop ? "pin.fill" : "pin",
                                  help: onTop ? "Stays on top of other windows. Click to turn off." : "Keep on top of other windows",
                                  isActive: onTop, size: 12) { onTop.toggle() }
                    BarIconButton(systemImage: "arrow.up.left.and.arrow.down.right",
                                  help: "Back to the full window", size: 12) {
                        dismissWindow(id: MacBeeApp.miniPlayerWindowID)
                    }
                }
            }
            TransportControls()
            ScrubberRow()
        }
        .padding(.horizontal, 16)
        .padding(.top, 30) // room for the window's close button
        .padding(.bottom, 14)
        .frame(width: 400)
        .background(theme.bar)
        .background(WindowLevelSetter(floating: onTop))
        .onDisappear {
            // Closing the mini player brings back the main window.
            openWindow(id: MacBeeApp.mainWindowID)
        }
    }
}
