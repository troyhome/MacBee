import AppKit
import MacBeeLibrary
import SwiftUI

/// Songs with more than one copy. The library already shows each song once (the copy from the folder highest
/// in Preferences > Library); here you can see every copy and deal with the extras: tick copies and take them
/// out of the library (the files stay on the drive) or delete them from the disk.
/// The folder menu limits the list to duplicates inside one folder.
struct DuplicatesView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var groups: [DuplicateGroup] = []
    @State private var removedCount = 0
    @State private var isLoaded = false
    @State private var filter = ""
    /// Only duplicates within this folder (nil = all folders).
    @State private var folderId: Int64?
    /// Ticked copies, by file path.
    @State private var selected = Set<String>()
    @State private var confirmRemoveAll = false
    @State private var deleteRequest: [DuplicateGroup.Copy] = []
    @State private var noTrashRequest: [DuplicateGroup.Copy] = []
    @State private var message: String?

    var body: some View {
        withDialogs(page)
            .task(id: library.revision) { await load() }
            .onChange(of: folderId) { selected = [] }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
            selectionBar
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 6)
            }
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(shownGroups) { group in
                    card(for: group)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .overlay { emptyState }
    }

    private func card(for group: DuplicateGroup) -> some View {
        DuplicateGroupCard(group: group, selected: $selected,
                           onRemove: { remove([$0]) },
                           onKeepOnly: { keep in remove(fullGroup(group.id).copies.filter { $0 != keep }) },
                           onDelete: { deleteRequest = $0 })
    }

    private func withDialogs<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog("Remove \(extraCount) extra copies from the library?", isPresented: $confirmRemoveAll) {
                Button("Remove Extra Copies") { remove(shownGroups.flatMap { extras(in: $0) }) }
            } message: {
                Text("Each song keeps the copy MacBee shows now. The other files stay on your drives, and you can bring them back with Restore Removed Copies.")
            }
            .confirmationDialog(deleteTitle, isPresented: deleteShown) {
                Button("Delete from Disk", role: .destructive) { delete(deleteRequest) }
            } message: {
                Text("Files on drives with a Trash go to the Trash, so you can get them back. If a drive has no Trash, MacBee asks again before deleting.")
            }
            .confirmationDialog(noTrashTitle, isPresented: noTrashShown) {
                Button("Delete Permanently", role: .destructive) { deletePermanently(noTrashRequest) }
            } message: {
                Text("\(noTrashFolders) has no Trash, so these files can't be put back afterwards.")
            }
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { !deleteRequest.isEmpty }, set: { if !$0 { deleteRequest = [] } })
    }

    private var noTrashShown: Binding<Bool> {
        Binding(get: { !noTrashRequest.isEmpty }, set: { if !$0 { noTrashRequest = [] } })
    }

    private var noTrashTitle: String {
        "Delete \(noTrashRequest.count) \(noTrashRequest.count == 1 ? "file" : "files") for good?"
    }

    // MARK: - Bars

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Picker("Duplicates in", selection: $folderId) {
                Text("All folders").tag(Int64?.none)
                ForEach(library.folders) { state in
                    Text("Only \(state.folder.name)").tag(Optional(state.id))
                }
            }
            .fixedSize()
            .help("Show copies across all folders, or only duplicates inside one folder")
            FilterField(prompt: "Search duplicates", text: $filter)
                .frame(width: 200)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Button(allExtrasSelected ? "Deselect All" : "Select All") {
                selected = allExtrasSelected ? [] : Set(shownGroups.flatMap { extras(in: $0) }.map(\.id))
            }
            .disabled(shownGroups.isEmpty)
            .help("Ticks every copy except the one each song shows")
            Text(selected.isEmpty ? "Tick copies to act on them" : "\(selected.count) selected")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
            Button("Remove from Library") { remove(selectedCopies) }
                .disabled(selected.isEmpty)
                .help("MacBee stops showing these copies; the files stay on the drive")
            Button("Delete from Disk…") { deleteRequest = selectedCopies }
                .disabled(selected.isEmpty)
            Spacer()
            if removedCount > 0 {
                Button("Restore Removed Copies (\(removedCount))") {
                    Task { try? await library.restoreRemovedCopies() }
                }
            }
            Button("Remove All Extra Copies…") { confirmRemoveAll = true }
                .disabled(shownGroups.isEmpty)
        }
    }

    // MARK: - What's listed

    /// Groups after the folder choice and search. With one folder chosen, only that folder's copies are listed,
    /// and only songs with two or more copies in it.
    private var shownGroups: [DuplicateGroup] {
        var result = groups
        if let folderId {
            result = result.compactMap { group in
                let copies = group.copies.filter { $0.track.folderId == folderId }
                return copies.count > 1 ? DuplicateGroup(id: group.id, copies: copies) : nil
            }
        }
        let query = filter.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { group in
                let song = group.shown
                return [song.displayTitle, song.displayArtist, song.displayAlbum].contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        return result
    }

    /// Copies other than the one the library shows (or, in a one-folder view, other than the first listed).
    private func extras(in group: DuplicateGroup) -> [DuplicateGroup.Copy] {
        let keep = group.copies.first { $0.track.id == group.id } ?? group.copies[0]
        return group.copies.filter { $0 != keep }
    }

    private func fullGroup(_ id: Int64) -> DuplicateGroup {
        groups.first { $0.id == id } ?? DuplicateGroup(id: id, copies: [])
    }

    private var selectedCopies: [DuplicateGroup.Copy] {
        groups.flatMap(\.copies).filter { selected.contains($0.id) }
    }

    private var allExtrasSelected: Bool {
        let all = Set(shownGroups.flatMap { extras(in: $0) }.map(\.id))
        return !all.isEmpty && all.isSubset(of: selected)
    }

    private var extraCount: Int { shownGroups.reduce(0) { $0 + extras(in: $1).count } }

    private var summary: String {
        guard isLoaded else { return "Looking for duplicates…" }
        if shownGroups.isEmpty { return "No duplicates." }
        return "\(shownGroups.count.formatted()) songs, \(extraCount.formatted()) extra copies"
    }

    private var deleteTitle: String {
        deleteRequest.count == 1 ? "Delete “\(deleteRequest[0].track.url.lastPathComponent)” from the disk?"
                                 : "Delete \(deleteRequest.count) files from the disk?"
    }

    private var noTrashFolders: String {
        let names = Set(noTrashRequest.map(\.folderName)).sorted()
        return names.count == 1 ? "“\(names[0])”" : "These drives"
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoaded && shownGroups.isEmpty {
            if !filter.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else {
                ContentUnavailableView("No duplicates", systemImage: "checkmark.circle",
                                       description: Text(folderId == nil ? "Every song in your library has just one copy."
                                                                         : "This folder has no song twice."))
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        groups = (try? await library.database.duplicateGroups()) ?? []
        removedCount = (try? await library.database.excludedTrackCount()) ?? 0
        let existing = Set(groups.flatMap(\.copies).map(\.id))
        selected.formIntersection(existing)
        isLoaded = true
    }

    private func remove(_ copies: [DuplicateGroup.Copy]) {
        let ids = copies.compactMap(\.track.id)
        guard !ids.isEmpty else { return }
        selected.subtract(copies.map(\.id))
        Task {
            do {
                try await library.removeFromLibrary(trackIds: ids)
                message = "Removed \(ids.count) \(ids.count == 1 ? "copy" : "copies") from the library. The files are still on the drive."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// Moves files to the Trash; files on drives without one are asked about again.
    private func delete(_ copies: [DuplicateGroup.Copy]) {
        var done: [DuplicateGroup.Copy] = []
        var noTrash: [DuplicateGroup.Copy] = []
        for copy in copies {
            do {
                try FileManager.default.trashItem(at: copy.track.url, resultingItemURL: nil)
                done.append(copy)
            } catch {
                noTrash.append(copy)
            }
        }
        finishDeleting(done, note: done.isEmpty ? nil : "Moved \(done.count) \(done.count == 1 ? "file" : "files") to the Trash.")
        if !noTrash.isEmpty {
            // Let this dialog close before showing the next one.
            DispatchQueue.main.async { noTrashRequest = noTrash }
        }
    }

    private func deletePermanently(_ copies: [DuplicateGroup.Copy]) {
        var done: [DuplicateGroup.Copy] = []
        var failed: [String] = []
        for copy in copies {
            do {
                try FileManager.default.removeItem(at: copy.track.url)
                done.append(copy)
            } catch {
                failed.append(copy.track.url.lastPathComponent)
            }
        }
        var note = "Deleted \(done.count) \(done.count == 1 ? "file" : "files")."
        if !failed.isEmpty { note += " Couldn't delete \(failed.joined(separator: ", "))." }
        finishDeleting(done, note: note)
    }

    private func finishDeleting(_ copies: [DuplicateGroup.Copy], note: String?) {
        selected.subtract(copies.map(\.id))
        let ids = copies.compactMap(\.track.id)
        Task {
            if !ids.isEmpty { try? await library.forgetDeletedFiles(trackIds: ids) }
            if let note { message = note }
        }
    }
}

/// One song and its copies, each with a tick box. SHOWN marks the copy the library shows.
private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    @Binding var selected: Set<String>
    let onRemove: (DuplicateGroup.Copy) -> Void
    let onKeepOnly: (DuplicateGroup.Copy) -> Void
    let onDelete: ([DuplicateGroup.Copy]) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ArtworkView(artworkId: group.shown.artworkId, pixelSize: 80, cornerRadius: 4)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.shown.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("\(group.shown.displayArtist) · \(group.shown.displayAlbum)")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
                .lineLimit(1)
            }
            ForEach(group.copies) { copy in
                row(for: copy)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }

    private func row(for copy: DuplicateGroup.Copy) -> CopyRow {
        let ticked = Binding<Bool>(
            get: { selected.contains(copy.id) },
            set: { isOn in
                if isOn { selected.insert(copy.id) } else { selected.remove(copy.id) }
            })
        return CopyRow(copy: copy, isShown: copy.track.id == group.id, isSelected: ticked,
                       onRemove: { onRemove(copy) }, onKeepOnly: { onKeepOnly(copy) }, onDelete: { onDelete([copy]) })
    }
}

/// One copy: tick box, SHOWN/COPY, folder, path (the whole path appears while the mouse is over it),
/// format and size, Show in Finder, and the ⋯ menu.
private struct CopyRow: View {
    let copy: DuplicateGroup.Copy
    let isShown: Bool
    @Binding var isSelected: Bool
    let onRemove: () -> Void
    let onKeepOnly: () -> Void
    let onDelete: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            label
            pathText
            Text(details)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
            finderButton
            actionsMenu
        }
        .padding(.leading, 20)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? theme.elevated : .clear))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var label: some View {
        HStack(spacing: 10) {
            Text(isShown ? "SHOWN" : "COPY")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isShown ? theme.accent : theme.textTertiary)
                .frame(width: 44, alignment: .leading)
            Text(copy.folderName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
        }
    }

    /// One line normally; the whole path while the mouse is over the row.
    private var pathText: some View {
        Text(copy.track.path)
            .font(.system(size: 11))
            .foregroundStyle(hovering ? theme.textPrimary : theme.textSecondary)
            .lineLimit(hovering ? nil : 1)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: hovering)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var finderButton: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([copy.track.url])
        } label: {
            Image(systemName: "folder")
        }
        .buttonStyle(.borderless)
        .help("Show in Finder")
    }

    private var actionsMenu: some View {
        Menu {
            if !isShown {
                Button("Remove from Library", action: onRemove)
            }
            Button("Keep Only This Copy", action: onKeepOnly)
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([copy.track.url]) }
            Divider()
            Button("Delete from Disk…", action: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Remove this copy, keep only this copy, show in Finder, or delete the file")
    }

    private var details: String {
        let size = ByteCountFormatter.string(fromByteCount: copy.track.fileSize, countStyle: .file)
        return "\(copy.track.formatSummary) · \(size)"
    }
}
