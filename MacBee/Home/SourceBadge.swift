import MacBeeLibrary
import SwiftUI

/// On the Media page: where songs play from, as a pop-up (Automatic, the network drive, Plex, Navidrome), with an icon
/// for the source in use right now.
struct SourceBadge: View {
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PreferencesStore.self) private var preferences
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var preferences = preferences
        let source = LibrarySource.current(library: library, preferences: preferences, app: app, player: player)
        HStack(spacing: 8) {
            Image(systemName: source.systemImage)
                .foregroundStyle(source == .local ? theme.accent : source == .unavailable ? theme.warning
                                 : source == .plex ? Color(hex: 0xE5A00D) : Color(hex: 0x0084FF))
            Picker("Play from", selection: $preferences.playbackSource) {
                Text("Automatic").tag(PlaybackSourcePreference.automatic)
                Text("Local network drive").tag(PlaybackSourcePreference.drive)
                Text("Plex").tag(PlaybackSourcePreference.plex)
                    .disabled(app.plex?.isSignedIn != true)
                Text("Navidrome").tag(PlaybackSourcePreference.navidrome)
                    .disabled(app.navidrome?.isSetUp != true)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 32)
        .background(Capsule().fill(theme.surface))
        .help("Where songs play from. Automatic uses your drive at home and Plex or Navidrome when it can't be reached. "
              + "Now playing from: \(source == .local ? "your drive" : source.title).")
    }
}
