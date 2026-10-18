import SwiftUI

/// Preferences > Sync: keep play counts, history, favorites, ratings and playlists in step with MacBee on your
/// other Macs on the same network.
struct SyncPreferences: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let sync = app.networkSync {
            SyncPreferencesForm(sync: sync)
        } else {
            ContentUnavailableView("The music library couldn't be opened", systemImage: "exclamationmark.triangle")
        }
    }
}

private struct SyncPreferencesForm: View {
    @Bindable var sync: NetworkSync
    @State private var asking: NetworkSync.Peer?
    @State private var enteredCode = ""

    var body: some View {
        Form {
            Section {
                Toggle("Sync with my other Macs", isOn: $sync.isEnabled)
                PreferenceNote("Keeps play counts, play history, favorites, ratings and playlists the same on your Macs. Turn this on on both Macs, on the same network. Nothing is deleted by a sync, and music files aren't copied: both Macs need the same music (the same drive, or a copy).")
                if sync.isEnabled {
                    LabeledContent("This Mac's code", value: sync.code)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    PreferenceNote("Your other Mac asks for this code the first time it syncs with this one.")
                }
            }
            if sync.isEnabled {
                Section("Your other Macs") {
                    if sync.peers.isEmpty {
                        PreferenceNote("Looking… Turn on “Sync with my other Macs” on the other Mac too, and keep MacBee open there.")
                    }
                    ForEach(sync.peers) { peer in
                        HStack {
                            Image(systemName: "laptopcomputer")
                            Text(peer.name)
                            Spacer()
                            if sync.syncingWith == peer.name {
                                Text("Syncing…").foregroundStyle(.secondary)
                            } else {
                                Button("Sync Now") { start(peer) }
                                    .disabled(sync.syncingWith != nil)
                            }
                        }
                    }
                }
            }
            if let message = sync.lastMessage {
                Section("Last sync") { PreferenceNote(message) }
            }
        }
        .formStyle(.grouped)
        .alert("Code for \(asking?.name ?? "")", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            TextField("6-digit code", text: $enteredCode)
            Button("Sync") {
                if let peer = asking { Task { await sync.sync(with: peer, code: enteredCode.trimmingCharacters(in: .whitespaces)) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the code shown in MacBee > Settings > Sync on \(asking?.name ?? "the other Mac").")
        }
    }

    private func start(_ peer: NetworkSync.Peer) {
        if let code = sync.savedCode(for: peer) {
            Task { await sync.sync(with: peer, code: code) }
        } else {
            enteredCode = ""
            asking = peer
        }
    }
}
