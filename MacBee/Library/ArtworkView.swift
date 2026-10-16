import MacBeeLibrary
import SwiftUI

/// A cover from the local cache, or a placeholder. Fills the space it's given.
struct ArtworkView: View {
    let artworkId: Int64?
    var pixelSize = 400
    var cornerRadius = Metrics.corner

    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var image: CGImage?

    var body: some View {
        theme.surface
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .task(id: artworkId) {
                image = await ArtworkLoader.shared.image(for: artworkId, in: library, pixelSize: pixelSize)
            }
    }
}
