import SwiftUI

/// Right side of the play bar: signal path, output device, exclusive mode, volume, queue, mini player.
struct OutputControls: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 6) {
            SignalPathBadge()
                .padding(.trailing, 6)
            OutputDeviceMenu()
            ExclusiveModeButton()
            EqualizerButton()
            VolumeControl()
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
