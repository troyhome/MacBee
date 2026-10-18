import AppKit
import MacBeeVideo
import SwiftUI

/// Movies and music videos with more than one file (another drive, folder or format), with the same tools as
/// the songs list: Duplicates in (one folder), search, tick boxes, Select All, Auto Select, Remove from Library
/// (the file stays on disk), Delete from Disk, Accept and Restore.
struct VideoDuplicatesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var filter = ""
    @State private var deleteRequest: [VideoFile] = []
    @State private var noTrashRequest: [VideoFile] = []
    @State private var message: String?
    /// Ticked copies, by path.
    @State private var selected = Set<String>()
    @State private var showingAccepted = false
    /// Only duplicates inside this folder (nil = all folders).
    @State private var folder: String?
    /// Videos whose copies were accepted (kept on purpose), by id. Saved on this Mac.
    @AppStorage("acceptedVideoDuplicates") private var acceptedRaw = ""

    struct Group: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let files: [VideoFile]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button("Look Again") { Task { await app.refreshVideos() } }
                    .disabled(app.videos.isScanning)
                    .help("Search the video and music folders again")
                Picker("Duplicates in", selection: $folder) {
                    Text("All folders").tag(String?.none)
                    ForEach(folders, id: \.self) { path in
                        Text("Only \((path as NSString).lastPathComponent)").tag(Optional(path))
                    }
                }
                .fixedSize()
                .help("Show copies across all folders, or only duplicates inside one folder")
                FilterField(prompt: "Search duplicate videos", text: $filter)
                    .frame(width: 220)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            HStack(spacing: 10) {
                Button(allExtrasSelected ? "Deselect All" : "Select All") {
                    selected = allExtrasSelected ? [] : Set(shown.flatMap { $0.files.dropFirst() }.map(\.path))
                }
                .disabled(shown.isEmpty)
                Button("Auto Select") { autoSelect() }
                    .disabled(shown.isEmpty)
                    .help("Ticks the smallest file of each video (when sizes match, a copy that isn't the shown one)")
                Button("Remove from Library") { removeSelected() }
                    .disabled(selected.isEmpty)
                    .help("MacBee stops showing these copies; the files stay on the drive")
                Button("Delete from Disk…") { deleteRequest = selectedFiles }
                    .disabled(selected.isEmpty)
                Button(showingAccepted ? "Un-accept" : "Accept") { accept(!showingAccepted) }
                    .disabled(selected.isEmpty)
                    .help(showingAccepted ? "List these videos' copies again" : "Keep these copies on purpose: they stop being listed here")
                Text(selected.isEmpty ? "" : "\(selected.count) selected")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Toggle(showingAccepted ? "Showing accepted" : "Show accepted (\(accepted.count))", isOn: $showingAccepted)
                    .toggleStyle(.button)
                if !app.videos.excluded.isEmpty {
                    Button("Restore Removed Copies (\(app.videos.excluded.count))") {
                        app.videos.restoreExcluded()
                        Task { await app.refreshVideos() }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(shown) { group in card(group) }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView("No duplicate videos", systemImage: "checkmark.circle",
                                           description: Text("Every movie and music video has just one copy. Paused music folders aren't included."))
                }
            }
        }
        .onChange(of: folder) { selected = [] }
        .confirmationDialog(deleteRequest.count == 1 ? "Delete “\(deleteRequest[0].url.lastPathComponent)” from the disk?"
                                                     : "Delete \(deleteRequest.count) videos from the disk?",
                            isPresented: Binding(get: { !deleteRequest.isEmpty }, set: { if !$0 { deleteRequest = [] } })) {
            Button("Delete from Disk", role: .destructive) { delete(deleteRequest) }
        } message: {
            Text("Files go to the Trash if the drive has one. If not, MacBee asks again before deleting.")
        }
        .confirmationDialog("Delete \(noTrashRequest.count) \(noTrashRequest.count == 1 ? "video" : "videos") for good?",
                            isPresented: Binding(get: { !noTrashRequest.isEmpty }, set: { if !$0 { noTrashRequest = [] } })) {
            Button("Delete Permanently", role: .destructive) { deletePermanently(noTrashRequest) }
        } message: {
            Text("The drive has no Trash, so these files can't be put back afterwards.")
        }
    }

    private var groups: [Group] {
        let catalog = app.videos.catalog
        let movies = catalog.movies.filter { $0.files.count > 1 }.map {
            Group(id: $0.id, title: $0.title, subtitle: ["Movie", $0.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                  files: $0.files)
        }
        let videos = catalog.musicVideos.filter { !($0.otherFiles ?? []).isEmpty }.map {
            Group(id: $0.id, title: $0.title, subtitle: "Music video · \($0.folderName)", files: $0.allFiles)
        }
        return movies + videos
    }

    /// Video folders and music folders, for the "Duplicates in" menu.
    private var folders: [String] {
        app.preferences.videoFolders + (app.library?.folders.filter { !$0.folder.isPaused }.map(\.folder.path) ?? [])
    }

    private func removeSelected() {
        let paths = Array(selected)
        app.videos.setExcluded(paths, true)
        selected = []
        message = "Removed \(paths.count) \(paths.count == 1 ? "copy" : "copies") from MacBee. The files are still on the drive."
    }

    private var shown: [Group] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        var listed = groups.filter { accepted.contains($0.id) == showingAccepted }
        if let folder {
            listed = listed.compactMap { group in
                let files = group.files.filter { $0.path.hasPrefix(folder + "/") }
                return files.count > 1 ? Group(id: group.id, title: group.title, subtitle: group.subtitle, files: files) : nil
            }
        }
        return query.isEmpty ? listed : listed.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var summary: String {
        shown.isEmpty ? "No duplicate videos." : "\(shown.count) videos have more than one copy."
    }

    private var accepted: Set<String> {
        Set(acceptedRaw.split(separator: "\n").map(String.init))
    }

    private var selectedFiles: [VideoFile] {
        groups.flatMap(\.files).filter { selected.contains($0.path) }
    }

    private var allExtrasSelected: Bool {
        let all = Set(shown.flatMap { $0.files.dropFirst() }.map(\.path))
        return !all.isEmpty && all.isSubset(of: selected)
    }

    /// Ticks each video's smallest file; with equal sizes, a copy other than the shown (first) one.
    private func autoSelect() {
        var picks = Set<String>()
        for group in shown {
            let indexed = Array(group.files.enumerated())
            if let smallest = indexed.min(by: { a, b in
                a.element.size != b.element.size ? a.element.size < b.element.size : (a.offset == 0 ? 1 : 0) < (b.offset == 0 ? 1 : 0)
            }) { picks.insert(smallest.element.path) }
        }
        selected = picks
    }

    private func accept(_ value: Bool) {
        let ids = shown.filter { group in group.files.contains { selected.contains($0.path) } }.map(\.id)
        var set = accepted
        if value { set.formUnion(ids) } else { set.subtract(ids) }
        acceptedRaw = set.sorted().joined(separator: "\n")
        selected = []
        message = value ? "Accepted \(ids.count) videos: they won't be listed again. Use Show accepted to undo."
                        : "\(ids.count) videos are listed again."
    }

    private func card(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(group.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            ForEach(Array(group.files.enumerated()), id: \.element.path) { index, file in
                VideoCopyRow(file: file, isShown: index == 0,
                             isSelected: Binding(get: { selected.contains(file.path) },
                                                 set: { isOn in if isOn { selected.insert(file.path) } else { selected.remove(file.path) } }),
                             onDelete: { deleteRequest = [file] })
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }

    private func delete(_ files: [VideoFile]) {
        var trashed = 0
        var noTrash: [VideoFile] = []
        for file in files {
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                trashed += 1
            } catch {
                noTrash.append(file)
            }
        }
        selected.subtract(files.map(\.path))
        if trashed > 0 {
            message = "Moved \(trashed) \(trashed == 1 ? "video" : "videos") to the Trash."
            Task { await app.refreshVideos() }
        }
        if !noTrash.isEmpty { DispatchQueue.main.async { noTrashRequest = noTrash } }
    }

    private func deletePermanently(_ files: [VideoFile]) {
        var deleted = 0
        var failed: [String] = []
        for file in files {
            do {
                try FileManager.default.removeItem(at: file.url)
                deleted += 1
            } catch {
                failed.append(file.url.lastPathComponent)
            }
        }
        message = "Deleted \(deleted) \(deleted == 1 ? "video" : "videos")." + (failed.isEmpty ? "" : " Couldn't delete \(failed.joined(separator: ", ")).")
        Task { await app.refreshVideos() }
    }
}

/// One copy of a video: SHOWN/COPY, the path (whole path while hovered), size, Show in Finder, Delete.
private struct VideoCopyRow: View {
    let file: VideoFile
    let isShown: Bool
    @Binding var isSelected: Bool
    let onDelete: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(isShown ? "SHOWN" : "COPY")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isShown ? theme.accent : theme.textTertiary)
                .frame(width: 44, alignment: .leading)
            Text(file.path)
                .font(.system(size: 11))
                .foregroundStyle(hovering ? theme.textPrimary : theme.textSecondary)
                .lineLimit(hovering ? nil : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: hovering)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(details)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete from Disk…")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? theme.elevated : .clear))
        .onHover { hovering = $0 }
    }

    private var details: String {
        let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        let quality = [file.is4K ? "4K" : nil, file.isHDR ? "HDR" : nil].compactMap { $0 }.joined(separator: " ")
        return [file.url.pathExtension.uppercased(), quality, size].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
