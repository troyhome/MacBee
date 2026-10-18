import AppKit
import MacBeeVideo
import SwiftUI

/// Movies and music videos with more than one file (another drive, folder or format). Videos aren't in the
/// music database, so there's no "remove from library" here: show a copy in Finder or delete it from the disk.
struct VideoDuplicatesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var filter = ""
    @State private var deleteRequest: VideoFile?
    @State private var noTrashRequest: VideoFile?
    @State private var message: String?

    struct Group: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let files: [VideoFile]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(groups.isEmpty ? "No duplicate videos." : "\(groups.count) videos have more than one copy.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button("Look Again") { Task { await app.refreshVideos() } }
                    .disabled(app.videos.isScanning)
                    .help("Search the video and music folders again")
                FilterField(prompt: "Search duplicate videos", text: $filter)
                    .frame(width: 220)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
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
        .confirmationDialog("Delete “\(deleteRequest?.url.lastPathComponent ?? "")” from the disk?",
                            isPresented: Binding(get: { deleteRequest != nil }, set: { if !$0 { deleteRequest = nil } })) {
            Button("Delete from Disk", role: .destructive) { if let file = deleteRequest { delete(file) } }
        } message: {
            Text("It goes to the Trash if the drive has one. If not, MacBee asks again before deleting.")
        }
        .confirmationDialog("Delete “\(noTrashRequest?.url.lastPathComponent ?? "")” for good?",
                            isPresented: Binding(get: { noTrashRequest != nil }, set: { if !$0 { noTrashRequest = nil } })) {
            Button("Delete Permanently", role: .destructive) { if let file = noTrashRequest { deletePermanently(file) } }
        } message: {
            Text("This drive has no Trash, so the file can't be put back afterwards.")
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

    private var shown: [Group] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? groups : groups.filter { $0.title.localizedCaseInsensitiveContains(query) }
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
                VideoCopyRow(file: file, isShown: index == 0, onDelete: { deleteRequest = file })
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
    }

    private func delete(_ file: VideoFile) {
        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            message = "Moved \(file.url.lastPathComponent) to the Trash."
            Task { await app.refreshVideos() }
        } catch {
            DispatchQueue.main.async { noTrashRequest = file }
        }
    }

    private func deletePermanently(_ file: VideoFile) {
        do {
            try FileManager.default.removeItem(at: file.url)
            message = "Deleted \(file.url.lastPathComponent)."
            Task { await app.refreshVideos() }
        } catch {
            message = "Couldn't delete \(file.url.lastPathComponent). \(error.localizedDescription)"
        }
    }
}

/// One copy of a video: SHOWN/COPY, the path (whole path while hovered), size, Show in Finder, Delete.
private struct VideoCopyRow: View {
    let file: VideoFile
    let isShown: Bool
    let onDelete: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
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
