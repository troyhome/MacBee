import AppKit
import MacBeeVideo
import SwiftUI

/// The mini player: the playing video in its own small window that stays above other windows, so you can
/// browse MacBee (or anything else) while it plays. Resize it freely; the picture scales to fit.
/// "Back to MacBee" returns the video to the main window; closing the window stops the video.
@MainActor
final class VideoMiniWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var app: AppModel?
    /// True while the window is being closed on purpose (going back to the app), not by the close button.
    private var closingForReturn = false

    func show(_ session: VideoSession, app: AppModel) {
        self.app = app
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: MiniVideoView(session: session, app: app))
        panel.title = session.current.title
        if !panel.isVisible { position(panel) }
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        closingForReturn = true
        panel.close()
        panel.contentView = nil
        closingForReturn = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = NSSize(width: 16, height: 9)
        panel.contentMinSize = NSSize(width: 256, height: 144)
        panel.backgroundColor = .black
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        return panel
    }

    /// Bottom-right corner of the screen the main window is on.
    private func position(_ panel: NSPanel) {
        let screen = NSApp.mainWindow?.screen ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 24, y: area.minY + 24))
    }

    func windowWillClose(_ notification: Notification) {
        guard !closingForReturn else { return }
        // The window's close button: stop the video.
        app?.closeVideo()
    }
}

/// What's inside the mini player window: the video, and buttons that appear while the mouse is over it.
private struct MiniVideoView: View {
    let session: VideoSession
    let app: AppModel
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.black
            MPVVideoView(player: session.player)
            if hovering { controls }
            VStack {
                Spacer()
                GeometryReader { geometry in
                    Rectangle()
                        .fill(app.themeStore.theme.accent)
                        .frame(width: geometry.size.width * progress)
                }
                .frame(height: 3)
            }
        }
        .ignoresSafeArea()
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering } }
        .onTapGesture(count: 2) { app.hideVideoMiniPlayer() }
        .environment(\.colorScheme, .dark)
    }

    private var controls: some View {
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing: 22) {
                button("gobackward.10", help: "Back 10 seconds") { session.player.seek(by: -10) }
                button(session.player.isPaused ? "play.fill" : "pause.fill", help: "Play/Pause", size: 26) {
                    session.player.togglePause()
                }
                button("goforward.10", help: "Forward 10 seconds") { session.player.seek(by: 10) }
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        app.hideVideoMiniPlayer()
                    } label: {
                        Label("Back to MacBee", systemImage: "arrow.down.right.and.arrow.up.left")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .help("Put the video back in the MacBee window (or double-click the video)")
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
                Spacer()
            }
        }
    }

    private var progress: CGFloat {
        let player = session.player
        return player.duration > 0 ? CGFloat(min(1, player.position / player.duration)) : 0
    }

    private func button(_ systemImage: String, help: String, size: CGFloat = 16, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
