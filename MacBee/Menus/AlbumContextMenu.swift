import AppKit
import MacBeeLibrary
import SwiftUI

/// Right-click menu for an album card.
struct AlbumContextMenu: View {
    let album: AlbumSummary
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation

    var body: some View {
        Button("Play") { Task { player.play(await player.tracks(of: album)) } }
        Button("Shuffle") { Task { player.playShuffled(await player.tracks(of: album)) } }
        Button("Play Next") { Task { player.playNext(await player.tracks(of: album)) } }
        Button("Add to Queue") { Task { player.addToQueue(await player.tracks(of: album)) } }
        AddToPlaylistMenu { await player.tracks(of: album) }
        Divider()
        EditTagsButton { await player.tracks(of: album) }
        Button("Go to Album") { navigation.openAlbum(album) }
        Button("Show in Finder") {
            Task {
                guard let first = await player.tracks(of: album).first else { return }
                NSWorkspace.shared.activateFileViewerSelecting([first.url])
            }
        }
    }
}
