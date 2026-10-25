import MacBeeLibrary
import SwiftUI

/// Round "…" button for a whole album, with the same items as the album page's "…" menu.
struct AlbumMoreMenu: View {
    let tracks: [Track]
    var diameter: CGFloat = 34

    var body: some View {
        MoreMenuButton(help: "Play Next, Add to Queue, Add to Playlist, Edit in TagBee, Show in Finder", diameter: diameter) {
            AlbumActionsMenu(tracks: tracks)
        }
    }
}
