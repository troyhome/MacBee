import AppKit
import MacBeeLibrary
import SwiftUI

/// Songs with more than one copy. The library already shows each song once (the copy from the folder highest
/// in Preferences > Library); here you can see every copy and deal with the extras: take them out of the
/// library (the files stay on the drive) or move the files to the Trash.
struct DuplicatesView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var groups: [DuplicateGroup] = []
    @State private var removedCount = 0
    @State private var isLoaded = false
    @State private var filter = ""
    @State private var confirmRemoveAll = false
    @State private var trashRequest: [DuplicateGroup.Copy] = []
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(shownGroups) { group in
                        DuplicateGroupCard(group: group,
                                           onRemove: { remove([$0]) },
                                           onKeepOnly: { keep in remove(group.copies.filter { $0 != keep }) },
                                           onTrash: { trashRequest = [$0] })
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .overlay { emptyState }
        }
        .task(id: library.revision) { await load() }
        .confirmationDialog("Remove \(extraCount) extra copies from the library?", isPresented: $confirmRemoveAll) {
            Button("Remove Extra Copies") { remove(groups.flatMap(\.extras)) }
        } message: {
            Text("Each song keeps the copy MacBee shows now. The other files stay on your drives, and you can bring them back with Restore Removed Copies.")
        }
        .confirmationDialog("Move \(trashRequest.first?.track.displayTitle ?? "this file") to the Trash?",
                            isPresented: Binding(get: { !trashRequest.isEmpty }, set: { if !$0 { trashRequest = [] } })) {
            Button("Move to Trash", role: .destructive) { trash(trashRequest) }
        } message: {
            Text(trashRequest.first.map { "\($0.track.path)\n\nYou can get it back from the Trash. Drives without a Trash (some network drives) are left untouched." } ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            FilterField(prompt: "Search duplicates", text: $filter)
                .frame(width: 220)
            if removedCount > 0 {
                Button("Restore Removed Copies (\(removedCount))") {
                    Task { try? await library.restoreRemovedCopies() }
                }
            }
            Button("Remove All Extra Copies…") { confirmRemoveAll = true }
                .disabled(groups.isEmpty)
        }
    }

    private var extraCount: Int { groups.reduce(0) { $0 + $1.extras.count } }

    private var summary: String {
        guard isLoaded else { return "Looking for duplicates…" }
        if groups.isEmpty { return "No duplicates." }
        return "\(groups.count.formatted()) songs have more than one copy (\(extraCount.formatted()) extra copies)."
    }

    private var shownGroups: [DuplicateGroup] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return groups }
        return groups.filter { group in
            let song = group.shown
            return [song.displayTitle, song.displayArtist, song.displayAlbum].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoaded && shownGroups.isEmpty {
            if filter.isEmpty {
                ContentUnavailableView("No duplicates", systemImage: "checkmark.circle",
                                       description: Text("Every song in your library has just one copy."))
            } else {
                ContentUnavailableView.search(text: filter)
            }
        }
    }

    private func load() async {
        groups = (try? await library.database.duplicateGroups()) ?? []
        removedCount = (try? await library.database.excludedTrackCount()) ?? 0
        isLoaded = true
    }

    private func remove(_ copies: [DuplicateGroup.Copy]) {
        let ids = copies.compactMap(\.track.id)
        guard !ids.isEmpty else { return }
        Task {
            do {
                try await library.removeFromLibrary(trackIds: ids)
                message = "Removed \(ids.count) \(ids.count == 1 ? "copy" : "copies") from the library. The files are still on the drive."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func trash(_ copies: [DuplicateGroup.Copy]) {
        var trashed: [Int64] = []
        var failed: [String] = []
        for copy in copies {
            do {
                try FileManager.default.trashItem(at: copy.track.url, resultingItemURL: nil)
                if let id = copy.track.id { trashed.append(id) }
            } catch {
                failed.append(copy.track.url.lastPathComponent)
            }
        }
        Task {
            if !trashed.isEmpty { try? await library.forgetDeletedFiles(trackIds: trashed) }
            message = failed.isEmpty
                ? "Moved to the Trash."
                : "Couldn't move \(failed.joined(separator: ", ")) to the Trash (the drive may not have one). Nothing was deleted."
        }
    }
}

/// One song and its copies. The first copy is the one the library shows.
private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let onRemove: (DuplicateGroup.Copy) -> Void
    let onKeepOnly: (DuplicateGroup.Copy) -> Void
    let onTrash: (DuplicateGroup.Copy) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            ForEach(Array(group.copies.enumerated()), id: \.element.id) { index, copy in
                HStack(spacing: 10) {
                    Text(index == 0 ? "SHOWN" : "COPY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(index == 0 ? theme.accent : theme.textTertiary)
                        .frame(width: 44, alignment: .leading)
                    Text(copy.folderName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 120, alignment: .leading)
                        .lineLimit(1)
                    Text(copy.track.path)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(copy.track.path)
                    Spacer(minLength: 8)
                    Text(details(copy.track))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.textTertiary)
                    Menu {
                        if index > 0 {
                            Button("Remove from Library") { onRemove(copy) }
                        }
                        Button("Keep Only This Copy") { onKeepOnly(copy) }
                        Divider()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([copy.track.url]) }
                        Divider()
                        Button("Move File to Trash…") { onTrash(copy) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Remove this copy, keep only this copy, or move the file to the Trash")
                }
                .padding(.leading, 46)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }

    private func details(_ track: Track) -> String {
        let size = ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file)
        return "\(track.formatSummary) · \(size)"
    }
}
