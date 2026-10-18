import AppKit
import SwiftUI

/// Shows an `MPVPlayer`'s picture. The player starts when the view first appears in a window.
public struct MPVVideoView: NSViewRepresentable {
    let player: MPVPlayer

    public init(player: MPVPlayer) {
        self.player = player
    }

    public func makeNSView(context: Context) -> VideoSurface {
        let view = VideoSurface()
        view.player = player
        return view
    }

    public func updateNSView(_ view: VideoSurface, context: Context) {}

    public final class VideoSurface: NSView {
        var player: MPVPlayer?

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            player?.start(in: self)
            layoutLayer()
        }

        public override func layout() {
            super.layout()
            layoutLayer()
        }

        public override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            layoutLayer()
        }

        private func layoutLayer() {
            guard let window else { return }
            player?.resize(to: bounds.size, scale: window.backingScaleFactor)
        }
    }
}
