import AppKit
import SwiftUI

/// MacBee → About MacBee: the standard About window with the version and a short credits line.
struct AboutCommand: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MacBee") { Self.showAboutPanel() }
        }
    }

    static func showAboutPanel() {
        let credits = NSAttributedString(
            string: "A bit-perfect, gapless music player for your own library.\n\n"
                + "Playback by SFBAudioEngine. Library by GRDB.\n"
                + "Video playback by mpv and FFmpeg (via MPVKit), used under the GNU LGPL 2.1. "
                + "Their source code: github.com/mpvkit/MPVKit",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
