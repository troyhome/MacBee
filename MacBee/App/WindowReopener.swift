import SwiftUI

/// Invisible helper that hands the app delegate what it needs from SwiftUI:
/// a way to reopen the main window, and the player for the Dock menu.
struct WindowReopener: View {
    let delegate: AppDelegate
    let player: PlayerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                delegate.player = player
                delegate.reopenWindow = { openWindow(id: MacBeeApp.mainWindowID) }
            }
    }
}
