import MacBeeLibrary
import SwiftUI

/// Album covers in a grid. Clicking opens the album; the play button on hover plays it.
struct AlbumGrid: View {
    let albums: [AlbumSummary]
    var showsArtist = true

    @Environment(PlayerViewModel.self) private var player
    @Environment(\.libraryNavigation) private var navigation

    private let columns = [GridItem(.adaptive(minimum: Metrics.albumTileMin, maximum: Metrics.albumTileMax),
                                    spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                ForEach(albums) { album in
                    AlbumTile(album: album, showsArtist: showsArtist) {
                        Task { await player.playAlbum(album) }
                    }
                    // Click or double-click opens the album; only the hover play button starts it.
                    .onTapGesture { navigation.openAlbum(album) }
                    .contextMenu { AlbumContextMenu(album: album) }
                }
            }
            .padding(24)
        }
    }
}
