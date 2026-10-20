import AppKit
import MacBeeLibrary
import SwiftUI

/// Copy To (roadmap Phase 4's "device sync", renamed by Troy; Device Sync is now the Mac-to-Mac sync): copies chosen
/// playlists, smart playlists, saved mixes or the whole library to a music player, SD card, USB drive or network
/// folder. First a scan reports what's new, changed, renamed or already there under another name; then you choose
/// how to go ahead and start the copy, which runs in the background (`CopyToRunner`) with Pause, Resume and Stop,
/// and ends with a report of what happened.
struct DeviceSyncView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlaylistStore.self) private var store
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @AppStorage("syncDestination") private var destination = ""
    /// Chosen items: "p:<playlist id>", "s:<smart playlist>", "m:<saved mix id>", one per line.
    @AppStorage("syncSelection") private var selectionRaw = ""
    @State private var savedMixes: [SavedMix] = []

    private var runner: CopyToRunner { app.copyTo }

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
        .task {
            savedMixes = (try? await library.database.savedMixes()) ?? []
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "debugCopyTo"), runner.phase == .idle {
                await runner.scan(sources: await sources(), device: destination)
                try? await Task.sleep(for: .seconds(4))
                runner.start()
            }
            #endif
        }
        .onChange(of: selectionRaw) { runner.forgetScan() }
        .onChange(of: destination) { runner.forgetScan() }
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

    // MARK: - Device, report and progress

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                deviceBox
                switch runner.phase {
                case .idle:
                    scanButton
                    PreferenceText("MacBee first looks at what's on the device and tells you what it would do. Nothing is copied or deleted until you press Start Copy.")
                case .scanning:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking at what's on the device… (songs under other names are checked by their tags, which takes a little longer)")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                case .ready:
                    if let scan = runner.scan { CopyToScanReport(scan: scan, runner: runner, freeSpace: freeSpace) }
                case .running, .paused:
                    CopyToProgress(runner: runner)
                case .finished:
                    if let report = runner.report { CopyToFinishedReport(report: report) }
                    scanButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var deviceBox: some View {
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
                .disabled(runner.isBusy || runner.hasUnfinishedCopy)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }

    private var scanButton: some View {
        Button {
            Task { await runner.scan(sources: await sources(), device: destination) }
        } label: {
            Label(runner.phase == .finished ? "Scan Again" : "Scan Device", systemImage: "magnifyingglass")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSync)
    }

    private var freeSpace: Int64? {
        let values = try? URL(fileURLWithPath: destination).resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
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
}

/// A short grey note.
private struct PreferenceText: View {
    let text: String
    init(_ text: String) { self.text = text }
    @Environment(\.theme) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }

private func songs(_ count: Int) -> String { count == 1 ? "1 song" : "\(count) songs" }

/// What the scan found, with a choice for each kind of change, and Start Copy.
private struct CopyToScanReport: View {
    let scan: DeviceSync.Scan
    @Bindable var runner: CopyToRunner
    let freeSpace: Int64?
    @Environment(\.theme) private var theme

    private var willCopy: Int64 {
        var total: Int64 = 0
        if runner.choices.copyNew { total += scan.newSongs.reduce(0) { $0 + $1.size } }
        if runner.choices.replaceChanged { total += (scan.changed + scan.moved).reduce(0) { $0 + $1.size } }
        if runner.choices.elsewhere != .skip { total += scan.foundElsewhere.reduce(0) { $0 + $1.size } }
        return total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What MacBee found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            row("plus.circle", "\(songs(scan.newSongs.count)) not on the device yet", detail: bytes(scan.newSongs.reduce(0) { $0 + $1.size })) {
                Toggle("Copy them", isOn: $runner.choices.copyNew).disabled(scan.newSongs.isEmpty)
            }
            row("arrow.triangle.2.circlepath", "\(songs(scan.changed.count + scan.moved.count)) changed since they were copied",
                detail: changedDetail) {
                Toggle("Replace them", isOn: $runner.choices.replaceChanged).disabled(scan.changed.isEmpty && scan.moved.isEmpty)
            }
            row("doc.on.doc", "\(songs(scan.foundElsewhere.count)) already there under a different name",
                detail: "Put there some other way (not by MacBee), with different file names") {
                Picker("", selection: $runner.choices.elsewhere) {
                    Text("Leave theirs").tag(DeviceSync.Choices.Elsewhere.skip)
                    Text("Replace with MacBee's copy").tag(DeviceSync.Choices.Elsewhere.replace)
                    Text("Keep both").tag(DeviceSync.Choices.Elsewhere.keepBoth)
                }
                .labelsHidden()
                .fixedSize()
                .disabled(scan.foundElsewhere.isEmpty)
            }
            row("trash", "\(songs(scan.unneeded.count)) MacBee copied before that aren't chosen any more", detail: nil) {
                Toggle("Remove them", isOn: $runner.choices.removeUnneeded).disabled(scan.unneeded.isEmpty)
            }
            row("checkmark.circle", "\(songs(scan.unchanged)) already there and up to date", detail: nil) { EmptyView() }
            row("folder", "\(scan.otherFiles) other files on the device", detail: "Not from MacBee and not matching any of your songs. Left alone.") { EmptyView() }
            if !scan.playlists.isEmpty {
                row("music.note.list", "\(scan.playlists.count) playlist files (.m3u8)", detail: "Written to the Playlists folder") { EmptyView() }
            }

            Divider()
            HStack(spacing: 12) {
                Button {
                    runner.start()
                } label: {
                    Label("Start Copy", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") { runner.forgetScan() }
                Text("\(bytes(willCopy)) to copy" + (freeSpace.map { " · \(bytes($0)) free on the device" } ?? ""))
                    .font(.system(size: 12))
                    .foregroundStyle(tooBig ? theme.warning : theme.textSecondary)
            }
            if tooBig {
                Text("That's more than the free space on the device. The copy pauses when it's full.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.warning)
            }
            PreferenceText("You can pause or stop at any time, and come back to a paused copy later, even after unplugging the device.")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }

    private var tooBig: Bool { freeSpace.map { willCopy > $0 } ?? false }

    private var changedDetail: String {
        var parts: [String] = []
        if !scan.changed.isEmpty { parts.append("\(scan.changed.count) with edited tags or cover") }
        if !scan.moved.isEmpty { parts.append("\(scan.moved.count) renamed (title, album, artist or number edited; the old copy is removed)") }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }

    private func row<Control: View>(_ icon: String, _ title: String, detail: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Spacer()
            control()
        }
    }
}

/// The copy in progress (or paused): a bar, the file being copied, Pause / Resume and Stop.
private struct CopyToProgress: View {
    let runner: CopyToRunner
    @Environment(\.theme) private var theme

    var body: some View {
        let total = runner.job?.operations.count ?? 0
        let done = runner.job?.next ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(runner.phase == .running ? "Copying…" : "Copy paused")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if runner.phase == .running {
                    Button("Pause") { runner.pause() }
                } else {
                    Button("Resume") { runner.resume() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Stop") { runner.stop() }
                    .help("Stop here. What's already copied stays on the device.")
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            Text("\(done) of \(total) steps · \(bytes(runner.job?.report.bytes ?? 0)) copied")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.textSecondary)
            if let file = runner.currentFile, runner.phase == .running {
                Text(file)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if case let .paused(reason) = runner.phase {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.warning)
            }
            PreferenceText("Copying carries on while you use the rest of MacBee.")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }
}

/// What the last copy did.
private struct CopyToFinishedReport: View {
    let report: DeviceSync.Report
    @Environment(\.theme) private var theme
    @State private var showFailures = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.stoppedEarly ? "Copy stopped" : "Copy finished")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            line("plus.circle", "\(songs(report.copiedNew)) copied")
            line("arrow.triangle.2.circlepath", "\(songs(report.replaced)) replaced with newer versions")
            line("pencil", "\(songs(report.moved)) renamed")
            if report.replacedElsewhere > 0 { line("doc.on.doc", "\(songs(report.replacedElsewhere)) under other names replaced with MacBee's copy") }
            if report.keptBoth > 0 { line("doc.on.doc", "\(songs(report.keptBoth)) copied next to the versions already there") }
            line("trash", "\(songs(report.removed)) removed")
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            if !report.failed.isEmpty {
                DisclosureGroup("\(report.failed.count) couldn't be done", isExpanded: $showFailures) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(report.failed, id: \.path) { failure in
                            Text("\(failure.path): \(failure.reason)")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .foregroundStyle(theme.warning)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }

    private var summary: String {
        var text = "\(bytes(report.bytes)) copied"
        if let finished = report.finished {
            let minutes = Int(finished.timeIntervalSince(report.started) / 60)
            text += minutes < 1 ? " in under a minute" : " in \(minutes) min"
        }
        if report.stoppedEarly { text += ". Stopped before the end: scan again to see what's left." }
        return text
    }

    private func line(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13))
            .foregroundStyle(theme.textPrimary)
    }
}
