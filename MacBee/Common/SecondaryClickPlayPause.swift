import AppKit
import SwiftUI

extension View {
    /// A two-finger click (secondary click / right-click) anywhere on this view pauses or resumes.
    /// Ordinary clicks, hovering and scrolling pass straight through to the view underneath.
    /// Used on the play bar, Now Playing and the mini player, which have no right-click menus of their own,
    /// so song, album and playlist menus elsewhere keep working.
    func secondaryClickPlaysPauses() -> some View {
        modifier(SecondaryClickPlayPause())
    }
}

private struct SecondaryClickPlayPause: ViewModifier {
    @Environment(PlayerViewModel.self) private var player

    func body(content: Content) -> some View {
        content.overlay(SecondaryClickCatcher { [player] in
            if player.currentTrack != nil { player.togglePlayPause() }
        })
    }
}

private struct SecondaryClickCatcher: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: (@MainActor () -> Void)?

        /// Only claims secondary clicks; everything else goes to the views below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .rightMouseUp,
                  super.hitTest(point) != nil else { return nil }
            return self
        }

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}
