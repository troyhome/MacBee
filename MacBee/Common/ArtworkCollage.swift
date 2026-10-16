import SwiftUI

/// Up to four covers in a 2 x 2 grid (fewer covers repeat to fill it). Used for playlists.
struct ArtworkCollage: View {
    let artworkIds: [Int64]
    let size: CGFloat
    var cornerRadius: CGFloat = 8
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if artworkIds.count <= 1 {
                ArtworkView(artworkId: artworkIds.first, pixelSize: Int(size * 2), cornerRadius: 0)
                    .overlay {
                        if artworkIds.isEmpty {
                            Image(systemName: "music.note.list")
                                .font(.system(size: size * 0.25))
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(theme.surface)
                        }
                    }
            } else {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(0..<2, id: \.self) { column in
                                ArtworkView(artworkId: artworkIds[(row * 2 + column) % artworkIds.count],
                                            pixelSize: Int(size), cornerRadius: 0)
                                    .frame(width: size / 2, height: size / 2)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
