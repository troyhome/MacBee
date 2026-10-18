import AppKit
import SwiftUI

/// The "Controls" menu, with keyboard shortcuts.
struct PlaybackCommands: Commands {
    let player: PlayerViewModel
    let preferences: PreferencesStore
    let equalizer: EqualizerStore
    @Environment(\.openWindow) private var openWindow

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
            Button("Equalizer…") { openWindow(id: MacBeeApp.equalizerWindowID) }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Button(equalizer.settings.isEnabled ? "Turn Equalizer Off" : "Turn Equalizer On") {
                equalizer.setEnabled(!equalizer.settings.isEnabled)
            }
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

/// The "Sync" menu: Copy To (playlists onto a player, card or folder: Track Studio > Copy To) and
/// Device Sync (MacBee on your other Mac: Settings > Sync).
struct SyncCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandMenu("Sync") {
            Button("Copy To…") {
                UserDefaults.standard.set(TagsSection.sync.rawValue, forKey: "tagsSection")
                if !app.isInTrackStudio { app.go(to: .tags) }
                NSApp.activate()
            }
            DeviceSyncMenuItem()
        }
    }
}

/// Opens Settings on the Sync tab.
private struct DeviceSyncMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Device Sync…") {
            UserDefaults.standard.set("sync", forKey: "preferencesTab")
            openSettings()
        }
    }
}
