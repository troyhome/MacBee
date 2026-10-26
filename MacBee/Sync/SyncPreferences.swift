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

    var body: some View {
        Form {
            Section {
                Toggle("Sync with my other Macs", isOn: $sync.isEnabled)
                PreferenceNote("Keeps play counts, play history, favorites, ratings, playlists and liked videos the same on your Macs. Turn this on on both Macs, on the same network. Music files aren't copied: both Macs need the same music (the same drive, or a copy).")
                if sync.isEnabled {
                    LabeledContent("This Mac's code", value: sync.code)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    PreferenceNote("Your other Mac asks for this code the first time it syncs with this one.")
                    Toggle("Keep my Macs in step automatically", isOn: $sync.syncsAutomatically)
                    PreferenceNote("After you've synced two Macs once, changes go across by themselves within about 20 seconds whenever MacBee is open on both: likes, favorites, ratings, playlists, plays and liked videos. Removing something on one Mac removes it on the other too. A copy of the library is saved each day before the first automatic sync.")
                }
            }
            if sync.isEnabled {
                Section(header: PreferenceHeader("Your other Macs")) {
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
                Section(header: PreferenceHeader("Last sync")) { PreferenceNote(message) }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $asking) { peer in
            SyncChoiceSheet(sync: sync, peer: peer, thisMac: sync.deviceName,
                            needsCode: sync.savedCode(for: peer) == nil) { asking = nil }
        }
    }

    /// Every sync starts with the choice of how (combine, or one Mac matching the other).
    private func start(_ peer: NetworkSync.Peer) {
        asking = peer
    }
}

/// Asked before every sync, in plain words: combine both Macs, or make one an exact copy of the other.
private struct SyncChoiceSheet: View {
    let sync: NetworkSync
    let peer: NetworkSync.Peer
    let thisMac: String
    let needsCode: Bool
    let onClose: () -> Void

    @AppStorage("lastSyncMode") private var modeRaw = NetworkSync.Mode.combine.rawValue
    @State private var code = ""
    @State private var confirmReplace = false

    private var mode: NetworkSync.Mode { NetworkSync.Mode(rawValue: modeRaw) ?? .combine }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync “\(thisMac)” and “\(peer.name)”")
                .font(.title2.bold())
            Text("Choose what should happen. Play counts and play history are always added together on both Macs, since those plays really happened.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $modeRaw) {
                choice(.combine, title: "Combine both Macs (recommended)",
                       detail: "Everything from both Macs ends up on both. Playlists with the same name (in the same folder) are joined. Nothing is deleted.")
                choice(.sendMine, title: "Make “\(peer.name)” match this Mac",
                       detail: "“\(peer.name)” gets this Mac's playlists and favorites; the ones only it has are deleted there. Use this when this Mac has your real library.")
                choice(.takeTheirs, title: "Make this Mac match “\(peer.name)”",
                       detail: "This Mac gets “\(peer.name)”'s playlists and favorites; the ones only this Mac has are deleted here. Use this when the other Mac has your real library.")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if mode != .combine {
                Label("Before anything is replaced, MacBee saves a copy of the library on the Mac being changed, in its Application Support > MacBee folder.",
                      systemImage: "externaldrive.badge.timemachine")
                    .font(.mbSecondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if needsCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Code shown on “\(peer.name)”")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("6-digit code", text: $code)
                        .frame(width: 140)
                    Text("On “\(peer.name)”: MacBee > Settings > Sync. Needed only the first time.")
                        .font(.mbCaption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(mode == .combine ? "Combine" : "Replace…") {
                    mode == .combine ? run() : (confirmReplace = true)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(needsCode && code.trimmingCharacters(in: .whitespaces).count < 6)
            }
        }
        .padding(24)
        .frame(width: 520)
        .confirmationDialog(confirmTitle, isPresented: $confirmReplace) {
            Button("Replace", role: .destructive) { run() }
        } message: {
            Text("Playlists and favorites only on \(mode == .sendMine ? "“\(peer.name)”" : "this Mac") will be deleted there. A backup copy is saved first.")
        }
    }

    private var confirmTitle: String {
        mode == .sendMine ? "Make “\(peer.name)” match this Mac?" : "Make this Mac match “\(peer.name)”?"
    }

    private func choice(_ value: NetworkSync.Mode, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.mbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
        .tag(value.rawValue)
    }

    private func run() {
        let entered = needsCode ? code.trimmingCharacters(in: .whitespaces) : (sync.savedCode(for: peer) ?? "")
        let chosen = mode
        onClose()
        Task { await sync.sync(with: peer, code: entered, mode: chosen) }
    }
}
