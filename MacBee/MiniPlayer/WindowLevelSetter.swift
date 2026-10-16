import AppKit
import SwiftUI

/// Keeps the window it sits in above other windows (or not).
struct WindowLevelSetter: NSViewRepresentable {
    let floating: Bool

    func makeNSView(context: Context) -> LevelView {
        let view = LevelView()
        view.floating = floating
        return view
    }

    func updateNSView(_ view: LevelView, context: Context) {
        view.floating = floating
    }

    final class LevelView: NSView {
        var floating = false {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            window?.level = floating ? .floating : .normal
        }
    }
}
