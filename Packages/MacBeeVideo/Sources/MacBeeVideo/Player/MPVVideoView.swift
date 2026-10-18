import AppKit
import SwiftUI

/// The view mpv draws into. Each `MPVPlayer` has exactly one, and it can move between windows (the main
/// window and the mini player window) without interrupting playback: mpv keeps drawing into the same layer.
public final class MPVSurfaceView: NSView {
    weak var player: MPVPlayer?

    override public init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        player?.start(in: self)
        layoutLayer()
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLayer()
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutLayer()
    }

    private func layoutLayer() {
        guard let window else { return }
        player?.resize(to: bounds.size, scale: window.backingScaleFactor)
    }
}

/// Shows an `MPVPlayer`'s picture. Wherever this view appears, it takes the player's surface.
public struct MPVVideoView: NSViewRepresentable {
    let player: MPVPlayer

    public init(player: MPVPlayer) {
        self.player = player
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        adopt(into: container)
        return container
    }

    public func updateNSView(_ container: NSView, context: Context) {
        if player.surface.superview !== container { adopt(into: container) }
    }

    private func adopt(into container: NSView) {
        let surface = player.surface
        surface.removeFromSuperview()
        surface.frame = container.bounds
        container.addSubview(surface)
    }
}
