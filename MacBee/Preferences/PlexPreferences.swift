import SwiftUI

/// Plex: sign in, pick the server and music library, match songs, and choose where songs play from.
struct PlexPreferences: View {
    @Environment(AppModel.self) private var app
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        if let plex = app.plex {
            PlexPreferencesForm(plex: plex, preferences: preferences)
        } else {
            ContentUnavailableView("The music library couldn't be opened", systemImage: "exclamationmark.triangle")
        }
    }
}

private struct PlexPreferencesForm: View {
    @Bindable var plex: PlexConnection
    @Bindable var preferences: PreferencesStore

    var body: some View {
        Form {
            Section {
                Picker("Play songs from", selection: $preferences.playbackSource) {
                    ForEach(PlaybackSourcePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                PreferenceNote("Also in the menu bar: Controls → Play Songs From. Away from home, each song is fetched from Plex as the original file before it plays, so it stays bit-perfect. Fetched songs are kept on this Mac (up to 3 GB) so they replay instantly.")
            } header: {
                Text("Where songs play from")
            }

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
                Section("Server") {
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
                            .foregroundStyle(plex.route == .unreachable ? .orange : .secondary)
                        Spacer()
                        Button("Check Connection") { Task { await plex.connect() } }
                    }
                    if plex.route == .relay {
                        PreferenceNote("Plex Relay is slow for lossless files. Turn on Remote Access in your Plex server's settings for faster playback away from home.")
                    }
                }

                Section("Songs") {
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
        .formStyle(.grouped)
    }

    private func signIn() {
        Task {
            do { try await plex.signIn() } catch { plex.message = "Couldn't start signing in. \(error.localizedDescription)" }
        }
    }
}
