import MacBeeLibrary
import SwiftUI

/// Right-click menu for an artist.
struct ArtistContextMenu: View {
    let artist: ArtistSummary
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        Button("Play") { Task { player.play(await player.tracks(of: artist)) } }
        Button("Shuffle") { Task { player.playShuffled(await player.tracks(of: artist)) } }
        Button("Play Next") { Task { player.playNext(await player.tracks(of: artist)) } }
        Button("Add to Queue") { Task { player.addToQueue(await player.tracks(of: artist)) } }
        AddToPlaylistMenu { await player.tracks(of: artist) }
    }
}
