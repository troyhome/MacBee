import MacBeeLibrary
import SwiftUI

/// Right-click menu for an artist.
struct ArtistContextMenu: View {
    let artist: ArtistSummary
    /// False on the artist's own page.
    var showsGoTo = true
    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        Button("Play") { Task { player.play(await player.tracks(of: artist)) } }
        Button("Shuffle") { Task { player.playShuffled(await player.tracks(of: artist)) } }
        Button("Play Next") { Task { player.playNext(await player.tracks(of: artist)) } }
        Button("Add to Queue") { Task { player.addToQueue(await player.tracks(of: artist)) } }
        Divider()
        Button("Make Mix from Artist") {
            Task {
                guard let seed = await player.tracks(of: artist).randomElement() else { return }
                await player.startMix(from: seed)
            }
        }
        Divider()
        Button("Add to Favorites") { Task { player.setFavorite(await player.tracks(of: artist), true) } }
        AddToPlaylistMenu { await player.tracks(of: artist) }
        if showsGoTo {
            Divider()
            Button("Go to Artist") { app.openArtist(key: artist.artistKey) }
        }
    }
}
