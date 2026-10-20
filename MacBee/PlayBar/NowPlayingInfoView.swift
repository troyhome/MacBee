import AppKit
import MacBeeLibrary
import SwiftUI

/// Artwork thumbnail and track info on the left of the play bar.
struct NowPlayingInfoView: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Button {
                app.showNowPlaying = true
            } label: {
                ArtworkView(artworkId: player.currentTrack?.artworkId, pixelSize: 160, cornerRadius: 4)
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)
            .help("Open Now Playing (right-click for more)")
            .contextMenu {
                if let track = player.currentTrack { PlayingSongMenu(track: track) }
            }

            if let track = player.currentTrack {
                TrackInfoText(track: track)
            } else {
                Text("Not playing")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

/// Right-click on the play bar's cover: things to do with the song that's playing.
private struct PlayingSongMenu: View {
    let track: Track
    @Environment(AppModel.self) private var app

    var body: some View {
        AddToPlaylistMenu { [track] }
        Divider()
        Button("Go to Album") { Task { await app.openAlbum(key: track.albumKey) } }
        Button("Go to Artist") { app.openArtist(key: track.artistKey) }
        Divider()
        EditTagsButton(tracks: [track])
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([track.url]) }
    }
}
