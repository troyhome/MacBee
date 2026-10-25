import AppKit
import MacBeeLibrary
import SwiftUI

/// Right-click menu for an album card.
struct AlbumContextMenu: View {
    let album: AlbumSummary
    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation

    var body: some View {
        Button("Play") { Task { player.play(await player.tracks(of: album)) } }
        Button("Shuffle") { Task { player.playShuffled(await player.tracks(of: album)) } }
        Button("Play Next") { Task { player.playNext(await player.tracks(of: album)) } }
        Button("Add to Queue") { Task { player.addToQueue(await player.tracks(of: album)) } }
        Divider()
        Button("Add to Favorites") { Task { player.setFavorite(await player.tracks(of: album), true) } }
        AddToPlaylistMenu { await player.tracks(of: album) }
        Divider()
        Button("Go to Album") { navigation.openAlbum(album) }
        Button("Go to Artist") { app.openArtist(key: album.artistKey) }
        Divider()
        EditTagsButton { await player.tracks(of: album) }
        Button("Show in Finder") {
            Task {
                guard let first = await player.tracks(of: album).first else { return }
                NSWorkspace.shared.activateFileViewerSelecting([first.url])
            }
        }
    }
}

/// The album page's and artist page's "…" menu (Play, Shuffle and the heart are buttons beside it).
struct AlbumActionsMenu: View {
    let tracks: [Track]
    /// Nil on the artist page (already there).
    var onArtist: (() -> Void)?
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        Button("Play Next") { player.playNext(tracks) }
        Button("Add to Queue") { player.addToQueue(tracks) }
        Divider()
        AddToPlaylistMenu { tracks }
        if let onArtist {
            Divider()
            Button("Go to Artist", action: onArtist)
        }
        Divider()
        EditTagsButton(tracks: tracks)
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(tracks.prefix(1).map(\.url))
        }
    }
}
