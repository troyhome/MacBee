import AppKit
import MacBeeLibrary
import SwiftUI

/// Device Sync (roadmap Phase 4): copies chosen playlists, smart playlists and saved mixes to a music player,
/// SD card, USB drive or network folder. Songs go into Artist/Album/## - Title, each playlist gets an .m3u8 in
/// a Playlists folder, only new or changed songs are copied, and songs MacBee put there earlier that no chosen
/// playlist needs are removed. Files MacBee didn't put there are left alone.
struct DeviceSyncView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlaylistStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("syncDestination") private var destination = ""
    /// Chosen items: "p:<playlist id>", "s:<smart playlist>", "m:<saved mix id>", one per line.
    @AppStorage("syncSelection") private var selectionRaw = ""
    @State private var savedMixes: [SavedMix] = []
    @State private var plan: DeviceSync.Plan?
    @State private var checking = false
    @State private var syncing = false
    @State private var progress: (done: Int, total: Int) = (0, 0)
    @State private var message: String?
    @State private var syncTask: Task<DeviceSync.Result, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            choices
                .frame(width: 320)
            summary
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { savedMixes = (try? await library.database.savedMixes()) ?? [] }
        .onChange(of: selectionRaw) { plan = nil }
        .onChange(of: destination) { plan = nil }
    }

    // MARK: - What to sync

    private var choices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Copy these to the device")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            List {
                Section("Everything") {
                    checkbox("Entire library", key: "all")
                }
                Section("Smart playlists") {
                    ForEach(SmartPlaylist.allCases) { smart in checkbox(smart.title, key: "s:\(smart.rawValue)") }
                }
                Section("Playlists") {
                    ForEach(store.allPlaylists) { playlist in
                        if let id = playlist.id {
                            let folder = store.folderPath(of: playlist)
                            checkbox(folder.isEmpty ? playlist.name : "\(folder) › \(playlist.name)", key: "p:\(id)")
                        }
                    }
                }
                if !savedMixes.isEmpty {
                    Section("Saved mixes") {
                        ForEach(savedMixes) { mix in checkbox(mix.title, key: "m:\(mix.id)") }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
        }
    }

    private func checkbox(_ title: String, key: String) -> some View {
        Toggle(title, isOn: Binding(get: { selection.contains(key) }, set: { on in
            var set = selection
            if on { set.insert(key) } else { set.remove(key) }
            selectionRaw = set.sorted().joined(separator: "\n")
        }))
        .toggleStyle(.checkbox)
        .lineLimit(1)
    }

    private var selection: Set<String> { Set(selectionRaw.split(separator: "\n").map(String.init)) }

    // MARK: - Device and summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.isEmpty ? "No device chosen" : destination)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(deviceDetails)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button("Choose Device or Folder…", action: chooseDestination)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))

            HStack(spacing: 10) {
                Button("Check What Changes") { Task { await check() } }
                    .disabled(!canSync || checking || syncing)
                Button(syncing ? "Syncing…" : "Sync Now") { Task { await sync() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSync || syncing)
                if syncing {
                    Button("Stop") { syncTask?.cancel() }
                }
            }

            if syncing, progress.total > 0 {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                Text("\(progress.done) of \(progress.total) files")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            if checking {
                Text("Looking at what's on the device…")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            if let plan {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(plan.copies.count) songs to copy (\(copySize(plan)))", systemImage: "arrow.down.doc")
                    Label("\(plan.unchanged) songs already there", systemImage: "checkmark.circle")
                    Label("\(plan.removals.count) songs to remove (no longer in the chosen playlists)", systemImage: "trash")
                    Label("\(plan.playlists.count) playlist files (.m3u8) in the Playlists folder", systemImage: "music.note.list")
                }
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            }
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
            }
            Text("Songs are copied as Artist / Album / ## - Title. Only new or changed songs are copied. MacBee only removes songs it copied there itself; your other files on the device are never touched.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var canSync: Bool {
        !destination.isEmpty && FileManager.default.fileExists(atPath: destination) && !selection.isEmpty
    }

    private var deviceDetails: String {
        guard !destination.isEmpty else { return "A music player, SD card, USB drive or network folder" }
        let url = URL(fileURLWithPath: destination)
        guard FileManager.default.fileExists(atPath: destination) else { return "Not connected" }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeNameKey])
        let free = values?.volumeAvailableCapacity.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return [values?.volumeName, free.map { "\($0) free" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func copySize(_ plan: DeviceSync.Plan) -> String {
        let bytes = plan.copies.reduce(Int64(0)) { sum, copy in
            sum + Int64((try? URL(fileURLWithPath: copy.source).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the music player, SD card or folder to copy your playlists to"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url.path
    }

    // MARK: - Doing it

    /// The chosen playlists with their songs.
    private func sources() async -> [DeviceSync.Source] {
        let database = library.database
        var result: [DeviceSync.Source] = []
        if selection.contains("all") {
            // The whole library: every song, no playlist file of its own.
            var everything = TrackFilter()
            everything.text = ""
            let tracks = (try? await database.tracks(matching: everything, limit: 1_000_000)) ?? []
            result.append(.init(name: "", tracks: tracks))
        }
        for key in selection.sorted() where key != "all" {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = Int64(parts[1]) else { continue }
            switch parts[0] {
            case "s":
                if let smart = SmartPlaylist(rawValue: Int(id)) {
                    result.append(.init(name: smart.title, tracks: (try? await database.tracks(for: smart)) ?? []))
                }
            case "p":
                if let playlist = store.playlist(id: id) {
                    let tracks = (try? await database.playlistEntries(playlistId: id).map(\.track)) ?? []
                    result.append(.init(name: playlist.name, tracks: tracks))
                }
            case "m":
                if let mix = savedMixes.first(where: { $0.id == id }) { result.append(.init(name: mix.title, tracks: mix.tracks)) }
            default: break
            }
        }
        return result
    }

    private func makePlan() async -> DeviceSync.Plan {
        let device = URL(fileURLWithPath: destination)
        let chosen = await sources()
        return await Task.detached(priority: .userInitiated) {
            let state = DeviceSync.inspect(device)
            return DeviceSync.plan(sources: chosen, existing: state.existing, previousManifest: state.manifest)
        }.value
    }

    private func check() async {
        checking = true
        message = nil
        plan = await makePlan()
        checking = false
    }

    private func sync() async {
        syncing = true
        message = nil
        progress = (0, 0)
        let current = await makePlan()
        plan = current
        let device = URL(fileURLWithPath: destination)
        let task = Task.detached(priority: .userInitiated) {
            DeviceSync.run(current, to: device) { done, total in
                Task { @MainActor in progress = (done, total) }
            }
        }
        syncTask = task // Stop cancels it; the copy loop checks between files
        let result = await task.value
        syncTask = nil
        syncing = false
        plan = nil
        var text = "Done: \(result.copied) copied, \(result.unchanged) already there, \(result.removed) removed."
        if !result.failed.isEmpty { text += " \(result.failed.count) couldn't be copied (device full or unplugged?)." }
        message = text
    }
}
