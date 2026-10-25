import SwiftUI

/// Right side of the play bar: the signal path, then the sound group (output, exclusive mode, equalizer, volume),
/// then the view group (lyrics, queue, mini player).
struct OutputControls: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            SignalPathBadge()
            // Sound: where it goes and how it sounds.
            HStack(spacing: 4) {
                OutputDeviceMenu()
                ExclusiveModeButton()
                EqualizerButton()
                VolumeControl()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface))
            // Views: lyrics, queue, mini player.
            HStack(spacing: 4) {
                BarIconButton(systemImage: "quote.bubble", help: app.showLyrics ? "Hide lyrics" : "Show lyrics",
                              isActive: app.showLyrics) { app.showLyrics.toggle() }
                BarIconButton(systemImage: "list.bullet", help: app.showQueue ? "Hide queue" : "Show queue",
                              isActive: app.showQueue) { app.showQueue.toggle() }
                BarIconButton(systemImage: "pip", help: "Switch to the mini player") {
                    // The main window comes back when the mini player is closed.
                    openWindow(id: MacBeeApp.miniPlayerWindowID)
                    dismissWindow(id: MacBeeApp.mainWindowID)
                }
            }
        }
    }
}
