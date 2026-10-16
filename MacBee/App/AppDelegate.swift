import AppKit

/// Keeps MacBee running (and playing) when its window is closed, like Apple Music.
/// Clicking the Dock icon brings the window back; only Quit stops the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the UI is up: reopens the main window.
    var reopenWindow: (() -> Void)?
    /// Set once the UI is up: used by the Dock menu.
    weak var player: PlayerViewModel?

    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Space plays/pauses, except while typing in a text field.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard event.keyCode == 49, modifiers.isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText),
                  let player = self?.player else { return event }
            player.togglePlayPause()
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { reopenWindow?() }
        return true
    }

    /// Right-click the Dock icon: Play/Pause, Next, Previous.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let player, player.currentTrack != nil else { return nil }
        let menu = NSMenu()
        if let track = player.currentTrack {
            let title = NSMenuItem(title: "\(track.displayTitle) — \(track.displayArtist)", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
        }
        menu.addItem(item(player.isPlaying ? "Pause" : "Play", #selector(playPause)))
        menu.addItem(item("Next", #selector(next)))
        menu.addItem(item("Previous", #selector(previous)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func playPause() { player?.togglePlayPause() }
    @objc private func next() { player?.next() }
    @objc private func previous() { player?.previous() }
}
