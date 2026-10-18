import AppKit
import MacBeeLibrary
import SwiftUI

/// The Library block on the Music page: the same controls as Settings > Library, in one tinted panel —
/// scan, force rescan, add a folder, drag folders into priority order, pause a folder, and Plex
/// (where songs play from, sign in or out).
struct LibraryStatusPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.theme) private var theme
    @State private var folderError: String?
    @State private var confirmRescan = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    library.scanAll()
                } label: {
                    Label("Scan Library", systemImage: "arrow.clockwise")
                }
                .disabled(library.isScanning)
                Button("Force Rescan…") { confirmRescan = true }
                    .disabled(library.isScanning || library.folders.isEmpty)
                Button("Add Folder…", action: chooseFolder)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }

            ForEach(library.folders) { state in
                FolderStatusRow(state: state)
                    .draggable(String(state.id))
                    .dropDestination(for: String.self) { items, _ in
                        guard let moved = items.first.flatMap(Int64.init) else { return false }
                        move(folder: moved, to: state.id)
                        return true
                    }
            }
            if library.folders.count > 1 {
                Text("Drag folders to set their priority. Switch one off to pause it.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }

            if let plex = app.plex {
                PlexStatusRow(plex: plex, preferences: preferences)
            }

            if let summary = lastScanSummary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            if let error = folderError ?? library.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.warning)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.modeTint))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.modeBorder, lineWidth: 1))
        .frame(maxWidth: 780, alignment: .leading)
        .confirmationDialog("Force a full rescan?", isPresented: $confirmRescan) {
            Button("Rescan Everything") { library.forceRescanAll() }
        } message: {
            Text("MacBee reads every song's tags again, even ones that look unchanged. On a network drive this can take a while. Play counts and favorites are kept.")
        }
    }

    private func move(folder id: Int64, to target: Int64) {
        var ids = library.folders.map(\.id)
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        Task {
            do { try await library.setFolderOrder(ids) } catch { folderError = error.localizedDescription }
        }
    }

    /// "Checking 2 Set Music…", "Reading 120 of 300", or "Last checked Today at 9:41 PM".
    private var statusText: String {
        if let progress = library.scanProgress {
            switch progress.phase {
            case .checking: return "Checking \(progress.folderName)…"
            case .reading: return "Reading \(progress.done) of \(progress.total) new or changed files…"
            case .finishing: return "Finishing…"
            }
        }
        guard let last = library.folders.compactMap(\.folder.lastScanAt).max() else { return "Not scanned yet" }
        return "Last checked \(Format.relativeDateTime(last))"
    }

    /// Summary of the last scan, only when something changed.
    private var lastScanSummary: String? {
        let reports = library.lastReports
        guard !reports.isEmpty else { return nil }
        let added = reports.map(\.added).reduce(0, +)
        let updated = reports.map(\.updated).reduce(0, +)
        let missing = reports.map(\.missing).reduce(0, +)
        let failed = reports.map(\.failedCount).reduce(0, +)
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if updated > 0 { parts.append("\(updated) updated") }
        if missing > 0 { parts.append("\(missing) missing") }
        if failed > 0 { parts.append("\(failed) couldn't be read") }
        if reports.contains(where: \.wasOffline) { parts.append("a folder was offline, nothing changed there") }
        return parts.isEmpty ? "Last scan: no changes." : "Last scan: " + parts.joined(separator: ", ") + "."
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await library.addFolder(url)
                folderError = nil
            } catch {
                folderError = error.localizedDescription
            }
        }
    }
}

private struct FolderStatusRow: View {
    let state: MusicLibrary.FolderState
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(theme.textTertiary)
                .help("Drag to change priority")
            Toggle("", isOn: Binding(get: { !state.folder.isPaused }, set: { on in
                Task { try? await library.setFolderPaused(id: state.id, !on) }
            }))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(state.folder.isPaused ? "Paused: switch on to include this folder's songs" : "Switch off to pause this folder")
            Image(systemName: state.isNetwork ? "externaldrive.connected.to.line.below" : "folder")
                .foregroundStyle(theme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.folder.path)
                    .foregroundStyle(state.folder.isPaused ? theme.textTertiary : theme.textPrimary)
                Text(state.isNetwork ? "Network drive" : "On this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            Text(state.folder.isPaused ? "Paused" : (state.isOnline ? "Connected" : "Not connected"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.folder.isPaused ? theme.textTertiary : (state.isOnline ? theme.good : theme.warning))
        }
        .font(.system(size: 13))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface))
    }
}

/// Plex on the Music page: account, where songs play from, sign in or out. The rest is in Settings > Library.
private struct PlexStatusRow: View {
    @Bindable var plex: PlexConnection
    @Bindable var preferences: PreferencesStore
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .foregroundStyle(Color(hex: 0xE5A00D))
            VStack(alignment: .leading, spacing: 1) {
                Text("Plex")
                    .foregroundStyle(theme.textPrimary)
                Text(account)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            Picker("Play from", selection: $preferences.playbackSource) {
                Text("Automatic").tag(PlaybackSourcePreference.automatic)
                Text("Drive").tag(PlaybackSourcePreference.drive)
                Text("Plex").tag(PlaybackSourcePreference.plex)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(!plex.isSignedIn)
            .help("Where songs play from: Automatic uses the drive at home and Plex when it can't be reached")
            switch plex.status {
            case .signedOut:
                Button("Sign In…") { Task { try? await plex.signIn() } }
            case .waitingForApproval:
                Button("Cancel") { plex.cancelSignIn() }
            case .signedIn:
                SettingsLink { Text("More…") }
                    .help("Server, music library and matching are in Settings > Library")
            }
        }
        .font(.system(size: 13))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface))
    }

    private var account: String {
        switch plex.status {
        case .signedOut: "Not signed in"
        case .waitingForApproval: "Approve MacBee in your browser…"
        case .signedIn: [plex.username.map { "Signed in as \($0)" } ?? "Signed in", plex.route.title].joined(separator: " · ")
        }
    }
}
