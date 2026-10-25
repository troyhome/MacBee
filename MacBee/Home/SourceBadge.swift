import MacBeeLibrary
import SwiftUI

/// On the Music page: which library songs come from right now ("Local Library" or "Plex Server"),
/// with a switch to flip between them. Off = your drives (Plex only steps in when they can't be reached).
struct SourceBadge: View {
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PreferencesStore.self) private var preferences
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let source = LibrarySource.current(library: library, preferences: preferences, plex: app.plex, player: player)
        let plexReady = app.plex?.isSignedIn == true
        HStack(spacing: 10) {
            Image(systemName: source == .plex ? "server.rack" : "externaldrive")
                .foregroundStyle(source == .plex ? Color(hex: 0xE5A00D) : theme.accent)
            Text(source == .plex ? "Plex Server" : (source == .local ? "Local Library" : "Library offline"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Toggle("Plex", isOn: Binding(
                get: { preferences.playbackSource == .plex },
                set: { preferences.playbackSource = $0 ? .plex : .automatic }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!plexReady)
                .font(.mbCaption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(theme.surface))
        .help(plexReady
              ? "Switch on to play everything from your Plex server; off plays from your drives (Plex fills in when they can't be reached)."
              : "Sign in to Plex in Preferences > Library to switch to your Plex server.")
    }
}
