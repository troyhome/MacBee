import MacBeeLibrary
import SwiftUI

/// A playlist's picture: the one chosen in Playlist Studio, or a collage of its album covers.
struct PlaylistArtwork: View {
    let playlist: Playlist
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    @Environment(PlaylistStore.self) private var store
    @State private var coverIds: [Int64] = []

    var body: some View {
        Group {
            if let artworkId = playlist.artworkId {
                ArtworkView(artworkId: artworkId, pixelSize: Int(max(size * 2, 80)), cornerRadius: cornerRadius)
                    .frame(width: size, height: size)
            } else if size < 40 {
                // Too small for a collage: just the first cover.
                ArtworkView(artworkId: coverIds.first, pixelSize: 80, cornerRadius: cornerRadius)
                    .frame(width: size, height: size)
            } else {
                ArtworkCollage(artworkIds: coverIds, size: size, cornerRadius: cornerRadius)
            }
        }
        .task(id: "\(playlist.id ?? -1)-\(store.contentRevision)") {
            guard playlist.artworkId == nil, let id = playlist.id else { return }
            coverIds = (try? await store.database.playlistSummary(playlistId: id).artworkIds) ?? []
        }
    }
}
