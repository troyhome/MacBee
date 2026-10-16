import AppKit
import MacBeeLibrary
import SwiftUI

/// Monitored folders, scanning, routine checks and missing files.
struct LibraryPreferences: View {
    @Environment(AppModel.self) private var app
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        if let library = app.library {
            LibraryPreferencesForm(library: library, preferences: preferences)
        } else {
            ContentUnavailableView("The music library couldn't be opened", systemImage: "exclamationmark.triangle",
                                   description: Text(app.libraryError ?? ""))
        }
    }
}

private struct LibraryPreferencesForm: View {
    let library: MusicLibrary
    @Bindable var preferences: PreferencesStore

    @AppStorage("showMissingFiles") private var showMissingFiles = false
    @State private var missing: [Track] = []
    @State private var folderToRemove: MusicLibrary.FolderState?
    @State private var confirmCleanUp = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Music folders") {
                ForEach(library.folders) { state in
                    FolderPreferenceRow(state: state) { folderToRemove = state }
                }
                if library.folders.isEmpty {
                    PreferenceNote("No folders yet.")
                }
                HStack {
                    Button("Add Folder…", action: addFolder)
                    Spacer()
                    Text(scanStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Scan Now") { library.scanAll() }
                        .disabled(library.isScanning || library.folders.isEmpty)
                }
                if let message {
                    PreferenceNote(message)
                }
            }

            Section("Routine check") {
                Picker("Check network folders for changes", selection: $preferences.routineCheck) {
                    ForEach(RoutineCheck.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: preferences.routineCheck) { library.periodicCheckInterval = preferences.routineCheck.interval }
                PreferenceNote("Picks up changes made from another computer. Changes on this Mac are noticed right away. Folders are also checked when a drive is reconnected.")
            }

            Section("Missing files") {
                Toggle("Show missing files", isOn: $showMissingFiles)
                PreferenceNote("Files that disappeared from a connected folder are hidden, not deleted, so their play counts come back if the file returns or was moved.")
                if showMissingFiles {
                    if missing.isEmpty {
                        PreferenceNote("No missing files.")
                    } else {
                        ForEach(missing.prefix(200), id: \.path) { track in
                            Text(track.path)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(track.path)
                        }
                        if missing.count > 200 {
                            PreferenceNote("…and \(missing.count - 200) more.")
                        }
                        Button("Remove Missing Files from Library…") { confirmCleanUp = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: "\(showMissingFiles)-\(library.revision)") {
            missing = showMissingFiles ? ((try? await library.database.missingTracks(limit: 2000)) ?? []) : []
        }
        .confirmationDialog("Remove \(folderToRemove?.folder.name ?? "this folder") from MacBee?",
                            isPresented: Binding(get: { folderToRemove != nil }, set: { if !$0 { folderToRemove = nil } })) {
            Button("Remove Folder", role: .destructive) {
                guard let state = folderToRemove, let id = state.folder.id else { return }
                Task {
                    do { try await library.removeFolder(id: id) } catch { message = error.localizedDescription }
                }
            }
        } message: {
            Text("Its songs, play counts and favorites are removed from MacBee. The music files themselves are not touched.")
        }
        .confirmationDialog("Remove \(missing.count) missing files from the library?", isPresented: $confirmCleanUp) {
            Button("Remove", role: .destructive) {
                Task {
                    do {
                        let count = try await library.removeMissingTracks()
                        message = "Removed \(count) missing files."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Their play counts and history are deleted too. This can't be undone.")
        }
    }

    private var scanStatus: String {
        if let progress = library.scanProgress {
            switch progress.phase {
            case .checking: return "Checking \(progress.folderName)…"
            case .reading: return "Reading \(progress.done) of \(progress.total)…"
            case .finishing: return "Finishing…"
            }
        }
        guard let last = library.folders.compactMap(\.folder.lastScanAt).max() else { return "" }
        return "Last checked \(Format.relativeDateTime(last))"
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await library.addFolder(url)
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

private struct FolderPreferenceRow: View {
    let state: MusicLibrary.FolderState
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isNetwork ? "externaldrive.connected.to.line.below" : "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.folder.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(state.isOnline ? "Connected" : "Not connected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.isOnline ? .green : .orange)
            Button("Remove…", action: onRemove)
        }
    }

    private var details: String {
        let kind = state.isNetwork ? "Network drive" : "On this Mac"
        guard let last = state.folder.lastScanAt else { return "\(kind) · not scanned yet" }
        return "\(kind) · last scan \(Format.relativeDateTime(last))"
    }
}
