import AppKit
import MacBeeLibrary
import SwiftUI

/// Monitored folders, scanning, routine checks, missing files, and the Plex server settings.
struct LibraryPreferences: View {
    @Environment(AppModel.self) private var app
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        if let library = app.library {
            LibraryPreferencesForm(library: library, plex: app.plex, preferences: preferences)
        } else {
            ContentUnavailableView("The music library couldn't be opened", systemImage: "exclamationmark.triangle",
                                   description: Text(app.libraryError ?? ""))
        }
    }
}

private struct LibraryPreferencesForm: View {
    let library: MusicLibrary
    let plex: PlexConnection?
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
                    FolderPreferenceRow(state: state, library: library) { folderToRemove = state }
                        .draggable(String(state.id))
                        .dropDestination(for: String.self) { items, _ in
                            guard let moved = items.first.flatMap(Int64.init) else { return false }
                            move(folder: moved, to: state.id)
                            return true
                        }
                }
                if library.folders.isEmpty {
                    PreferenceNote("No folders yet.")
                } else if library.folders.count > 1 {
                    PreferenceNote("Drag folders to set their priority: when the same song is in more than one folder, MacBee shows the copy from the folder highest in the list, and plays another folder's copy if that one can't be reached. Switch a folder off to leave its songs out without removing it.")
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

            Section("Artists") {
                Toggle("Hide compilation-only artists from Artists view", isOn: $preferences.hideCompilationOnlyArtists)
                PreferenceNote("Leaves out artists who only appear on compilations, unless they also have an album of their own.")
            }

            VideoFoldersSection(preferences: preferences)

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

            if let plex {
                PlexPreferenceSections(plex: plex, preferences: preferences)
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

    /// Puts a dragged folder where the folder it was dropped on is, and saves the new priority order.
    private func move(folder id: Int64, to target: Int64) {
        var ids = library.folders.map(\.id)
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        Task {
            do { try await library.setFolderOrder(ids) } catch { message = error.localizedDescription }
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
    let library: MusicLibrary
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to change priority")
            Toggle("", isOn: Binding(get: { !state.folder.isPaused }, set: { on in
                Task { try? await library.setFolderPaused(id: state.id, !on) }
            }))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(state.folder.isPaused ? "Paused: this folder's songs are left out. Switch on to include them."
                                         : "Switch off to leave this folder's songs out without removing it")
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
            Text(state.folder.isPaused ? "Paused" : (state.isOnline ? "Connected" : "Not connected"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.folder.isPaused ? Color.secondary : (state.isOnline ? Color.green : Color.orange))
            Button("Remove…", action: onRemove)
        }
    }

    private var details: String {
        let kind = state.isNetwork ? "Network drive" : "On this Mac"
        guard let last = state.folder.lastScanAt else { return "\(kind) · not scanned yet" }
        return "\(kind) · last scan \(Format.relativeDateTime(last))"
    }
}

/// Folders with movies and TV shows for the Videos page (music videos are found in the music folders).
private struct VideoFoldersSection: View {
    @Bindable var preferences: PreferencesStore
    @Environment(AppModel.self) private var app

    var body: some View {
        Section("Video folders") {
            ForEach(preferences.videoFolders, id: \.self) { path in
                let paused = preferences.pausedVideoFolders.contains(path)
                let connected = FileManager.default.fileExists(atPath: path)
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(get: { !paused }, set: { app.setVideoFolder(path, paused: !$0) }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .help(paused ? "Paused: this folder's videos are left out. Switch on to include them."
                                     : "Switch off to leave this folder's videos out without removing it")
                    Image(systemName: "film.stack")
                        .foregroundStyle(.secondary)
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(paused ? .secondary : .primary)
                    Spacer()
                    Text(paused ? "Paused" : connected ? "Connected" : "Not connected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(paused ? Color.secondary : connected ? .green : .orange)
                    Button("Remove") {
                        preferences.videoFolders.removeAll { $0 == path }
                        FolderAccess.shared.forget(path)
                        preferences.pausedVideoFolders.removeAll { $0 == path }
                        Task { await app.refreshVideos() }
                    }
                }
            }
            if preferences.videoFolders.isEmpty {
                PreferenceNote("No video folders yet. Add the folder or drive with your movies and TV shows.")
            }
            HStack {
                Button("Add Video Folder…", action: add)
                Spacer()
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Scan Videos Now") { Task { await app.refreshVideos() } }
                    .disabled(app.videos.isScanning)
            }
            PreferenceNote("MacBee plays MKV, MP4, MOV, AVI and more, including 4K and HDR. Posters and genres come from picture and .nfo files next to the videos.")
        }
    }

    private var status: String {
        if app.videos.isScanning { return "Looking for videos…" }
        let catalog = app.videos.catalog
        guard catalog.scannedAt != nil else { return "" }
        return "\(catalog.movies.count) movies, \(catalog.shows.count) shows"
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        FolderAccess.shared.remember(url)
        preferences.addVideoFolder(url.path)
        Task { await app.refreshVideos() }
    }
}
