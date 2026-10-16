import AppKit
import MacBeeLibrary
import SwiftUI

/// Right-click menu for one or more songs.
struct TrackContextMenu: View {
    let tracks: [Track]
    let onPlay: () -> Void
    /// Shown on playlist pages.
    var onRemoveFromPlaylist: (() -> Void)?
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        if !tracks.isEmpty {
            let allFavorites = tracks.allSatisfy(player.isFavorite)
            Button("Play", action: onPlay)
            Button("Play Next") { player.playNext(tracks) }
            Button("Add to Queue") { player.addToQueue(tracks) }
            Divider()
            Button(allFavorites ? "Remove from Favorites" : "Add to Favorites") {
                player.setFavorite(tracks, !allFavorites)
            }
            AddToPlaylistMenu { tracks }
            if let onRemoveFromPlaylist {
                Button("Remove from Playlist", action: onRemoveFromPlaylist)
            }
            Divider()
            EditTagsButton(tracks: tracks)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(tracks.map(\.url))
            }
        }
    }
}
