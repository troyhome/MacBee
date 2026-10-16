import SwiftUI

/// The "Controls" menu, with keyboard shortcuts.
struct PlaybackCommands: Commands {
    let player: PlayerViewModel
    let preferences: PreferencesStore

    var body: some Commands {
        CommandMenu("Controls") {
            // Space is handled in AppDelegate so it still types spaces in text fields.
            Button("Play / Pause") { player.togglePlayPause() }
            Button("Next") { player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous") { player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button(player.queue.isShuffled ? "Turn Shuffle Off" : "Turn Shuffle On") { player.toggleShuffle() }
            Button("Repeat: \(player.queue.repeatMode.title)") { player.cycleRepeat() }
            Divider()
            Picker("Play Songs From", selection: Binding(get: { preferences.playbackSource },
                                                         set: { preferences.playbackSource = $0 })) {
                Text("Automatic (drive at home, Plex when away)").tag(PlaybackSourcePreference.automatic)
                Text("Always the Network Drive").tag(PlaybackSourcePreference.drive)
                Text("Always Plex").tag(PlaybackSourcePreference.plex)
            }
        }
    }
}
