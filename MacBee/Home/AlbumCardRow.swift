import MacBeeLibrary
import SwiftUI

/// A horizontal row of album cards. Clicking opens the album; the play button on hover plays it.
struct AlbumCardRow: View {
    let albums: [AlbumSummary]
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation

    var body: some View {
        HorizontalCarousel {
            LazyHStack(alignment: .top, spacing: 18) {
                ForEach(albums) { album in
                    AlbumTile(album: album) { Task { await player.playAlbum(album) } }
                        .frame(width: 160)
                        // Click or double-click opens the album; only the hover play button starts it.
                        .onTapGesture { navigation.openAlbum(album) }
                        .contextMenu { AlbumContextMenu(album: album) }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 6) // room for the hover shadow
        }
    }
}
