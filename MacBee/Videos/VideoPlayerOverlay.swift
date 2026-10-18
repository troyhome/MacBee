import AVKit
import SwiftUI

/// Plays a music video over the window, with the standard macOS video controls.
/// Esc or the close button returns to MacBee. Music pauses while a video plays.
struct VideoPlayerOverlay: View {
    let video: VideoItem
    @Environment(AppModel.self) private var app
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let player {
                VideoPlayer(player: player)
            }
            HStack {
                CircleButton(systemImage: "chevron.down", help: "Close (Esc)", tinted: false) { app.closeVideo() }
                Text(video.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4)
                    .lineLimit(1)
                Spacer()
                CircleButton(systemImage: "arrow.up.left.and.arrow.down.right", help: "Full screen", tinted: false) {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
            }
            .padding(20)
        }
        .environment(\.colorScheme, .dark)
        .background(
            Button("Close Video") { app.closeVideo() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .task(id: video.url) {
            let player = AVPlayer(url: video.url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
