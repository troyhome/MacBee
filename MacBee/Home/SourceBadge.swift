import MacBeeLibrary
import SwiftUI

/// On the Media page: which library songs come from right now ("Local Library", "Plex Server", "Navidrome Server"),
/// with a switch to flip between them. Off = your drives (the server only steps in when they can't be reached).
struct SourceBadge: View {
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PreferencesStore.self) private var preferences
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let source = LibrarySource.current(library: library, preferences: preferences, app: app, player: player)
        // The server the switch turns on: Plex when signed in, otherwise Navidrome.
        let server: (preference: PlaybackSourcePreference, name: String)? =
            app.plex?.isSignedIn == true ? (.plex, "Plex") : app.navidrome?.isSetUp == true ? (.navidrome, "Navidrome") : nil
        HStack(spacing: 10) {
            Image(systemName: source.systemImage)
                .foregroundStyle(source == .local ? theme.accent : source == .unavailable ? theme.warning
                                 : source == .plex ? Color(hex: 0xE5A00D) : Color(hex: 0x0084FF))
            Text(source == .local ? "Local Library" : source == .unavailable ? "Library offline" : "\(source.title) Server")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Toggle(server?.name ?? "Server", isOn: Binding(
                get: { preferences.playbackSource == .plex || preferences.playbackSource == .navidrome },
                set: { preferences.playbackSource = $0 ? (server?.preference ?? .automatic) : .automatic }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(server == nil)
                .font(.mbCaption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(theme.surface))
        .help(server.map { "Switch on to play everything from \($0.name); off plays from your drives (\($0.name) fills in when they can't be reached)." }
              ?? "Connect Plex or Navidrome in Settings > Library to play from a server.")
    }
}
