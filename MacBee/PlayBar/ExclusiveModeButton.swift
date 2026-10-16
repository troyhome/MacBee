import SwiftUI

/// One-click exclusive (hog) mode.
struct ExclusiveModeButton: View {
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        let isOn = player.engine.settings.exclusiveMode
        BarIconButton(systemImage: isOn ? "lock.fill" : "lock.open",
                      help: isOn ? "Exclusive mode is on: other apps can't play through this device. Click to turn off."
                                 : "Exclusive mode is off. Click to stop other apps mixing in.",
                      isActive: isOn) { player.toggleExclusiveMode() }
    }
}
