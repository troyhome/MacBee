import AppKit
import MacBeeLibrary
import SwiftUI

/// Full-window Now Playing: big cover over a blurred copy of it, song details, the full signal path,
/// scrubber and controls. Esc or the arrow at the top left closes it; the other button toggles full screen.
struct NowPlayingView: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let coverSize = max(200, min(geometry.size.height * 0.6, geometry.size.width * 0.4, 560))
            ZStack {
                // Blurred cover fills the window behind everything.
                ArtworkView(artworkId: player.currentTrack?.artworkId, pixelSize: 600, cornerRadius: 0)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: 70)
                    .overlay(Color.black.opacity(0.55))
                    .clipped()

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 16)
                    if let track = player.currentTrack {
                        HStack(alignment: .center, spacing: 48) {
                            ArtworkView(artworkId: track.artworkId, pixelSize: 1200, cornerRadius: 10)
                                .frame(width: coverSize, height: coverSize)
                                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                            details(for: track)
                                .frame(maxWidth: 560, alignment: .leading)
                        }
                        .padding(.horizontal, 40)
                    } else {
                        Text("Nothing is playing")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 16)
                }
                .padding(24)
            }
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .background(closeShortcut)
        .secondaryClickPlaysPauses()
    }

    private var topBar: some View {
        HStack {
            CircleButton(systemImage: "chevron.down", help: "Close (Esc)", tinted: false) { close() }
            Spacer()
            CircleButton(systemImage: "arrow.up.left.and.arrow.down.right", help: "Full screen", tinted: false) {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
    }

    private func details(for track: Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(track.displayTitle)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
            Text(track.displayArtist)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
            Text(track.displayAlbum)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
            SignalPathLine()
                .padding(.top, 4)
            ScrubberRow()
                .padding(.top, 18)
            TransportControls()
                .frame(maxWidth: .infinity)
            LyricsPlaceholder()
                .padding(.top, 18)
        }
    }

    /// Invisible button so Esc closes the view.
    private var closeShortcut: some View {
        Button("Close Now Playing") { close() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
    }

    private func close() {
        app.showNowPlaying = false
    }
}

/// Reserved space for lyrics (a later phase).
private struct LyricsPlaceholder: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.bubble")
            Text("Lyrics will appear here in a future version.")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.45))
    }
}
