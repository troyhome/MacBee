import AppKit
import SwiftUI

/// Keeps the window it sits in above other windows (or not). With `onZoom`, the window's green button runs it
/// (the mini player uses it to go back to the full window).
struct WindowLevelSetter: NSViewRepresentable {
    let floating: Bool
    var onZoom: (() -> Void)?

    func makeNSView(context: Context) -> LevelView {
        let view = LevelView()
        view.onZoom = onZoom
        view.floating = floating
        return view
    }

    func updateNSView(_ view: LevelView, context: Context) {
        view.onZoom = onZoom
        view.floating = floating
    }

    final class LevelView: NSView {
        var floating = false {
            didSet { apply() }
        }
        var onZoom: (() -> Void)?

        @objc private func zoomClicked(_ sender: Any?) { onZoom?() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            window?.level = floating ? .floating : .normal
            if onZoom != nil, let zoom = window?.standardWindowButton(.zoomButton) {
                zoom.isEnabled = true
                zoom.target = self
                zoom.action = #selector(zoomClicked(_:))
            }
        }
    }
}
