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

/// Right-click on the play bar's cover: the song menu, without Play (it's already playing).
private struct PlayingSongMenu: View {
    let track: Track

    var body: some View {
        TrackContextMenu(tracks: [track], onPlay: nil)
    }
}
