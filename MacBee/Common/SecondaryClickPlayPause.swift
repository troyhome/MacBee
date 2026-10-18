import AppKit
import OSLog
import SwiftUI


extension View {
    /// A two-finger click (secondary click / right-click) anywhere on this view pauses or resumes.
    /// Used on the play bar, Now Playing and the mini player, which have no right-click menus of their own,
    /// so song, album and playlist menus elsewhere keep working.
    func secondaryClickPlaysPauses() -> some View {
        background(SecondaryClickZone())
    }
}

/// Marks an area of a window. `SecondaryClickMonitor` checks every secondary click against these areas.
private struct SecondaryClickZone: NSViewRepresentable {
    func makeNSView(context: Context) -> ZoneView { ZoneView() }
    func updateNSView(_ view: ZoneView, context: Context) {}

    final class ZoneView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                SecondaryClickMonitor.shared.zones.removeAll { $0.view === self || $0.view == nil }
            } else if !SecondaryClickMonitor.shared.zones.contains(where: { $0.view === self }) {
                SecondaryClickMonitor.shared.zones.append(.init(view: self))
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil } // never takes clicks itself
    }
}

/// Watches the app's own secondary clicks (not other apps') and, inside a zone, plays or pauses instead of
/// letting the click through.
private let clickLog = Logger(subsystem: "com.troyhomenchuk.MacBee", category: "SecondaryClick")

@MainActor
final class SecondaryClickMonitor {
    static let shared = SecondaryClickMonitor()

    struct Zone { weak var view: NSView? }
    fileprivate var zones: [Zone] = []
    private var monitor: Any?

    /// Starts watching. `action` runs for a secondary click inside a zone.
    func start(action: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let used = MainActor.assumeIsolated {
                guard let self else { return false }
                let inZone = self.isInZone(event)
                clickLog.notice("secondary click \(event.type.rawValue, privacy: .public): zones \(self.zones.count, privacy: .public), live \(self.zones.filter { $0.view?.window != nil }.count, privacy: .public), in zone \(inZone, privacy: .public)")
                guard inZone else { return false }
                if event.type == .rightMouseDown { action() }
                return true
            }
            return used ? nil : event // a used click opens no menu
        }
    }

    private func isInZone(_ event: NSEvent) -> Bool {
        zones.contains { zone in
            guard let view = zone.view, let window = view.window, window === event.window, !view.isHiddenOrHasHiddenAncestor
            else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }
}
