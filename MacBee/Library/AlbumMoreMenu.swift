import AppKit
import MacBeeLibrary
import SwiftUI

/// Round "…" button for a whole album: Play Next, Add to Queue, Add to Playlist, Send to TagBee, Show in Finder.
/// Used on album cards on artist pages and on the album page, so both offer the same things.
struct AlbumMoreMenu: View {
    let tracks: [Track]
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Menu {
            Button("Play Next") { player.playNext(tracks) }
            Button("Add to Queue") { player.addToQueue(tracks) }
            AddToPlaylistMenu { tracks }
            Divider()
            EditTagsButton(tracks: tracks)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(tracks.prefix(1).map(\.url))
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(hovering ? theme.elevated : theme.surface))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Play Next, Add to Queue, Add to Playlist, Send to TagBee, Show in Finder")
    }
}
