import AppKit
import MacBeeLibrary
import SwiftUI

/// Right-click menu for one or more songs. Every music menu uses the same order: play actions, mixes,
/// favorites and playlists, go-to links, then file actions.
struct TrackContextMenu: View {
    let tracks: [Track]
    /// Nil for the song that's already playing (the play bar's cover).
    let onPlay: (() -> Void)?
    /// Shown on playlist pages.
    var onRemoveFromPlaylist: (() -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player

    init(tracks: [Track], onPlay: (() -> Void)?, onRemoveFromPlaylist: (() -> Void)? = nil) {
        self.tracks = tracks
        self.onPlay = onPlay
        self.onRemoveFromPlaylist = onRemoveFromPlaylist
    }

    var body: some View {
        if !tracks.isEmpty {
            let allFavorites = tracks.allSatisfy(player.isFavorite)
            let single = tracks.count == 1 ? tracks.first : nil
            if let onPlay {
                Button("Play", action: onPlay)
                Button("Play Next") { player.playNext(tracks) }
                Button("Add to Queue") { player.addToQueue(tracks) }
                Divider()
            }
            if let track = single {
                Button("Make Mix from Song") { Task { await player.startMix(from: track) } }
                Button("Play More from \(track.displayArtist)") { Task { await player.playMore(fromArtistOf: track) } }
                Divider()
            }
            Button(allFavorites ? "Remove from Favorites" : "Add to Favorites") {
                player.setFavorite(tracks, !allFavorites)
            }
            AddToPlaylistMenu { tracks }
            if let onRemoveFromPlaylist {
                Button("Remove from Playlist", action: onRemoveFromPlaylist)
            }
            if let track = single {
                Divider()
                Button("Go to Album") { Task { await app.openAlbum(key: track.albumKey) } }
                Button("Go to Artist") { app.openArtist(key: track.artistKey) }
            }
            Divider()
            EditTagsButton(tracks: tracks)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(tracks.map(\.url))
            }
        }
    }
}
