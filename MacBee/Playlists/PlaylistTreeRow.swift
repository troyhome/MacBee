import MacBeeLibrary
import SwiftUI

/// One playlist or folder in the sidebar, with its children when it's an open folder.
struct PlaylistTreeRow: View {
    let node: PlaylistNode
    let depth: Int

    @Environment(AppModel.self) private var app
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    /// Open folders, saved as "3,7,12".
    @AppStorage(Profiles.key("openPlaylistFolders")) private var openFolders = ""
    @State private var hovering = false
    @State private var targeted = false

    private var playlist: Playlist { node.playlist }
    private var isFolder: Bool { playlist.isFolder }
    private var isOpen: Bool { openFolderIds.contains(node.id) }
    private var isSelected: Bool {
        guard !isFolder else { return false }
        return app.isPlaylistHighlighted(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row
            if isFolder && isOpen {
                ForEach(node.children) { child in
                    PlaylistTreeRow(node: child, depth: depth + 1)
                }
                if node.children.isEmpty {
                    Text("Empty folder")
                        .font(.mbCaption)
                        .foregroundStyle(theme.textTertiary)
                        .padding(.leading, 46 + CGFloat(depth + 1) * 12)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            if isFolder {
                Image(systemName: "chevron.right")
                    .font(.mbLabel)
                    .foregroundStyle(theme.textTertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10, height: 1)
            }
            if isFolder {
                Image(systemName: "folder")
                    .font(.mbSecondary)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 22)
            } else {
                PlaylistArtwork(playlist: playlist, size: 22, cornerRadius: 4)
            }
            Text(playlist.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .lineLimit(2) // long names wrap instead of cutting off early
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10 + CGFloat(depth) * 12)
        .padding(.trailing, 8)
        .frame(minHeight: 30)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 6).fill(background))
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if !isFolder { Task { await playAll(shuffled: false) } } }
        .onTapGesture { isFolder ? toggleOpen() : app.selectPlaylistInSidebar(node.id) }
        .contextMenu { menu }
        .draggable(DragPayload.playlist(node.id).string)
        .dropDestination(for: String.self) { strings, _ in
            guard let first = strings.first, let payload = DragPayload(string: first) else { return false }
            return handleDrop(payload)
        } isTargeted: { targeted = $0 }
        .help(isFolder ? "" : app.isInStudio || app.isInTrackStudio
              ? "Click to show its songs in the studio. Drag it into the studio to add or browse it."
              : "Click to open, double-click to play. Drop songs here to add them.")
    }

    private var background: Color {
        if targeted { return theme.accent.opacity(0.25) }
        if isSelected { return theme.elevated }
        return hovering ? theme.surface : .clear
    }

    private var menu: some View {
        PlaylistContextMenu(playlist: playlist, openFolder: open)
    }

    /// Playlists dropped on a folder go inside it; dropped on a playlist they go just above it.
    /// Songs, albums and artists dropped on a playlist are added to it.
    private func handleDrop(_ payload: DragPayload) -> Bool {
        switch payload {
        case let .playlist(id):
            guard id != node.id else { return false }
            if isFolder {
                open()
                Task { await store.move(id, toFolder: node.id, at: Int.max) }
            } else {
                let siblings = store.playlists
                    .filter { $0.parentFolderId == playlist.parentFolderId && $0.id != id }
                    .sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
                let index = siblings.firstIndex { $0.id == node.id } ?? siblings.count
                Task { await store.move(id, toFolder: playlist.parentFolderId, at: index) }
            }
            return true
        default:
            guard !isFolder else { return false }
            Task {
                let tracks = await store.tracks(for: payload)
                await store.add(tracks, to: node.id)
            }
            return true
        }
    }

    private func playAll(shuffled: Bool) async {
        let tracks = (try? await store.database.playlistEntries(playlistId: node.id).map(\.track)) ?? []
        shuffled ? player.playShuffled(tracks) : player.play(tracks)
    }

    // MARK: Open folders

    private var openFolderIds: Set<Int64> {
        Set(openFolders.split(separator: ",").compactMap { Int64($0) })
    }

    private func toggleOpen() {
        isOpen ? close() : open()
    }

    private func open() {
        var ids = openFolderIds
        ids.insert(node.id)
        openFolders = ids.map(String.init).joined(separator: ",")
    }

    private func close() {
        var ids = openFolderIds
        ids.remove(node.id)
        openFolders = ids.map(String.init).joined(separator: ",")
    }
}
