import SwiftUI

/// Plex settings, shown in the Library tab of Preferences: sign in, pick the server and music library,
/// and match songs. These are Form sections; the Library tab's Form holds them.
struct PlexPreferenceSections: View {
    @Bindable var plex: PlexConnection
    @Bindable var preferences: PreferencesStore
    @Environment(\.theme) private var theme

    var body: some View {
        Section("Plex account") {
            switch plex.status {
            case .signedOut:
                HStack {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sign In with Plex…") { signIn() }
                }
                PreferenceNote("Your browser opens plex.tv. Sign in there and approve MacBee; this window updates by itself.")
            case .waitingForApproval:
                HStack {
                    Text("Waiting for you to approve MacBee in your browser…")
                    Spacer()
                    Button("Cancel") { plex.cancelSignIn() }
                }
            case .signedIn:
                HStack {
                    Text(plex.username.map { "Signed in as \($0)" } ?? "Signed in")
                    Spacer()
                    Button("Sign Out") { plex.signOut() }
                }
            }
        }

        if plex.status == .signedIn {
            Section("Plex server and library") {
                Picker("Server", selection: $plex.selectedServerId) {
                    if plex.servers.isEmpty { Text("No servers found").tag(String?.none) }
                    ForEach(plex.servers) { Text($0.name).tag(Optional($0.id)) }
                }
                if plex.sections.count > 1 {
                    Picker("Music library", selection: $plex.selectedSectionKey) {
                        ForEach(plex.sections) { Text($0.title).tag(Optional($0.key)) }
                    }
                }
                HStack {
                    Text(plex.route.title)
                        .foregroundStyle(plex.route == .unreachable ? theme.warning : theme.textSecondary)
                    Spacer()
                    Button("Check Connection") { Task { await plex.connect() } }
                }
                if plex.route == .relay {
                    PreferenceNote("Plex Relay is slow for lossless files. Turn on Remote Access in your Plex server's settings for faster playback away from home.")
                }
            }

            Section("Plex matching") {
                HStack {
                    Text(plex.isMatching ? "Matching songs with Plex…"
                         : "\(plex.linkedCount.formatted()) songs can play from Plex")
                    Spacer()
                    Button("Match Again") { Task { await plex.matchLibrary() } }
                        .disabled(plex.isMatching)
                }
                PreferenceNote("Songs are matched by their folder and file name, so Plex adds no duplicates. Match again after adding music.")
            }
        }

        if let message = plex.message {
            Section {
                PreferenceNote(message)
            }
        }
    }

    private func signIn() {
        Task {
            do { try await plex.signIn() } catch { plex.message = "Couldn't start signing in. \(error.localizedDescription)" }
        }
    }
}
