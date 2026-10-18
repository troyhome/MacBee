import AppKit
import MacBeeVideo
import SwiftUI

/// The full-window video player (mpv: MKV, MP4, 4K, HDR). Controls appear when the mouse moves and hide after
/// a few seconds. Space pauses, ← / → skip 10 seconds, Esc closes. The mini player button moves the video to
/// its own small window so you can keep using MacBee.
struct VideoPlayerOverlay: View {
    let session: VideoSession

    @Environment(AppModel.self) private var app
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black
            MPVVideoView(player: session.player)
            VideoControls(player: session.player, playback: session.current, visible: controlsVisible,
                          onMini: { app.showVideoMiniPlayer() }, onClose: { app.closeVideo() })
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onContinuousHover { _ in showControls() }
        .onTapGesture(count: 2) { NSApp.keyWindow?.toggleFullScreen(nil) }
        .onTapGesture { session.player.togglePause() }
        .background(shortcuts)
        .onAppear { showControls() }
    }

    private func showControls() {
        if !controlsVisible { withAnimation(.easeOut(duration: 0.15)) { controlsVisible = true } }
        NSCursor.setHiddenUntilMouseMoves(false)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !session.player.isPaused else { return }
            withAnimation(.easeOut(duration: 0.3)) { controlsVisible = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    /// Invisible buttons for the keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("Close Video") { app.closeVideo() }.keyboardShortcut(.cancelAction)
            Button("Play/Pause") { session.player.togglePause(); showControls() }.keyboardShortcut(.space, modifiers: [])
            Button("Back 10 Seconds") { session.player.seek(by: -10); showControls() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Forward 10 Seconds") { session.player.seek(by: 10); showControls() }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
