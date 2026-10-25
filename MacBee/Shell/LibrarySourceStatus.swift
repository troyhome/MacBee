import MacBeeLibrary
import SwiftUI

/// Where songs are coming from right now.
enum LibrarySource {
    case local, plex, unavailable

    var title: String {
        switch self {
        case .local: "Local library"
        case .plex: "Plex"
        case .unavailable: "Library offline"
        }
    }

    var systemImage: String {
        switch self {
        case .local: "externaldrive"
        case .plex: "server.rack"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    /// Follows the same rules as `PlaybackRouter`: the playing song wins, then the "Play songs from" choice,
    /// then (on Automatic) whether a music folder can be reached.
    @MainActor
    static func current(library: MusicLibrary, preferences: PreferencesStore, plex: PlexConnection?,
                        player: PlayerViewModel) -> LibrarySource {
        if player.isPlayingFromPlex { return .plex }
        let plexReady = plex?.isSignedIn == true
        switch preferences.playbackSource {
        case .drive: return .local
        case .plex: return plexReady ? .plex : .local
        case .automatic:
            if library.folders.contains(where: \.isOnline) { return .local }
            return plexReady ? .plex : .unavailable
        }
    }
}

/// Small line under Playlist Studio: the active source (Local or Plex) and a Force Rescan button.
struct LibrarySourceStatus: View {
    let collapsed: Bool
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PreferencesStore.self) private var preferences
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var confirmRescan = false

    var body: some View {
        let source = LibrarySource.current(library: library, preferences: preferences, plex: app.plex, player: player)
        Group {
            if collapsed {
                Image(systemName: source.systemImage)
                    .font(.mbSecondary)
                    .foregroundStyle(color(source))
                    .frame(maxWidth: .infinity)
                    .help("Playing from: \(source.title)")
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(source))
                        .frame(width: 6, height: 6)
                    Text(source.title)
                        .font(.mbCaption)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        confirmRescan = true
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(library.isScanning || library.folders.isEmpty)
                    .help("Force Rescan: read every song's tags again")
                }
                .help("Playing from: \(source.title)")
            }
        }
        .confirmationDialog("Force a full rescan?", isPresented: $confirmRescan) {
            Button("Rescan Everything") { library.forceRescanAll() }
        } message: {
            Text("MacBee reads every song's tags again, even ones that look unchanged. On a network drive this can take a while. Play counts and favorites are kept.")
        }
    }

    private func color(_ source: LibrarySource) -> Color {
        switch source {
        case .local: theme.good
        case .plex: Color(hex: 0xE5A00D)
        case .unavailable: theme.warning
        }
    }
}
