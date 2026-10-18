import AppKit
import MacBeeVideo
import SwiftUI

/// Plays a video over the whole window with mpv (MKV, MP4, 4K, HDR). Controls appear when the mouse moves
/// and hide after a few seconds. Space pauses, ← / → skip 10 seconds, Esc closes. Music pauses while it plays.
/// Where you stopped is remembered; when an episode ends, the next one starts.
/// The mini player button shrinks it to a small box in the corner (drag it anywhere) so you can keep browsing.
struct VideoPlayerOverlay: View {
    let playback: VideoPlayback

    @Environment(AppModel.self) private var app
    @State private var player = MPVPlayer()
    @State private var current: VideoPlayback?
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var lastSaved = Date.distantPast
    /// Where the mini player has been dragged to, from its corner.
    @State private var miniOffset = CGSize.zero
    @State private var dragStart: CGSize?

    private static let miniSize = CGSize(width: 384, height: 216)

    var body: some View {
        let shown = current ?? playback
        let mini = app.videoIsMini
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                if !mini {
                    Color.black
                }
                // The video stays the same view in both sizes, so playback carries on while it shrinks or grows.
                ZStack {
                    Color.black
                    MPVVideoView(player: player)
                    if mini {
                        MiniVideoControls(player: player, onExpand: { setMini(false) }, onClose: close)
                    } else {
                        VideoControls(player: player, playback: shown, visible: controlsVisible,
                                      onMini: { setMini(true) }, onClose: close)
                    }
                }
                .frame(width: mini ? Self.miniSize.width : geometry.size.width,
                       height: mini ? Self.miniSize.height : geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: mini ? 10 : 0))
                .shadow(color: .black.opacity(mini ? 0.5 : 0), radius: 16, y: 6)
                .contentShape(Rectangle())
                .onContinuousHover { _ in showControls() }
                .onTapGesture(count: 2) { mini ? setMini(false) : NSApp.keyWindow?.toggleFullScreen(nil) }
                .onTapGesture { player.togglePause() }
                .gesture(miniDrag(in: geometry.size), including: mini ? .all : .subviews)
                .offset(mini ? miniOffset : .zero)
                .padding(.trailing, mini ? 20 : 0)
                .padding(.bottom, mini ? Metrics.playBarHeight + 20 : 0)
            }
        }
        .environment(\.colorScheme, .dark)
        .background { if !mini { shortcuts } }
        .onAppear {
            current = playback
            start(playback, resume: true)
            showControls()
        }
        .onChange(of: player.position) { _, position in
            // Save every 10 seconds, so a crash or quit loses little.
            if Date().timeIntervalSince(lastSaved) > 10 {
                lastSaved = Date()
                app.videos.savePosition(position, duration: player.duration, for: shown.file.path)
            }
        }
        .onChange(of: player.reachedEnd) { _, ended in
            if ended { playNext() }
        }
        .onDisappear {
            app.videos.savePosition(player.position, duration: player.duration, for: shown.file.path)
            player.shutdown()
        }
    }

    private func start(_ item: VideoPlayback, resume: Bool) {
        let startAt = resume ? app.videos.position(of: item.file.path) : 0
        // The player needs its view on screen first; loading right after appearing is fine,
        // because mpv queues the file until the view is ready.
        DispatchQueue.main.async { player.load(item.file.url, startAt: startAt) }
    }

    private func playNext() {
        guard let shown = current else { return }
        app.videos.savePosition(player.duration, duration: player.duration, for: shown.file.path)
        guard let next = shown.upNext.first else { return }
        var item = VideoPlayback(title: next.title, subtitle: next.subtitle, file: next.file, likeId: shown.likeId)
        item.upNext = Array(shown.upNext.dropFirst())
        current = item
        start(item, resume: false)
    }

    private func close() {
        app.closeVideo()
    }

    private func setMini(_ value: Bool) {
        if !value { miniOffset = .zero }
        withAnimation(.easeOut(duration: 0.25)) { app.videoIsMini = value }
    }

    /// Moves the mini player, keeping it inside the window.
    private func miniDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? miniOffset
                dragStart = start
                let maxLeft = -(size.width - Self.miniSize.width - 40)
                let maxUp = -(size.height - Self.miniSize.height - Metrics.playBarHeight - 40)
                miniOffset = CGSize(width: min(0, max(maxLeft, start.width + value.translation.width)),
                                    height: min(0, max(maxUp, start.height + value.translation.height)))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func showControls() {
        if !controlsVisible { withAnimation(.easeOut(duration: 0.15)) { controlsVisible = true } }
        NSCursor.setHiddenUntilMouseMoves(false)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !player.isPaused else { return }
            withAnimation(.easeOut(duration: 0.3)) { controlsVisible = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    /// Invisible buttons for the keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("Close Video") { close() }.keyboardShortcut(.cancelAction)
            Button("Play/Pause") { player.togglePause(); showControls() }.keyboardShortcut(.space, modifiers: [])
            Button("Back 10 Seconds") { player.seek(by: -10); showControls() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Forward 10 Seconds") { player.seek(by: 10); showControls() }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
