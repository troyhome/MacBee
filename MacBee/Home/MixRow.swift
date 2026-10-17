import MacBeeLibrary
import SwiftUI

/// Suggested mixes as cards with a four-cover collage. Click shuffles the mix.
struct MixRow: View {
    let mixes: [Mix]

    var body: some View {
        HorizontalCarousel {
            HStack(alignment: .top, spacing: 18) {
                ForEach(mixes) { MixCard(mix: $0) }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 6)
        }
    }
}

private struct MixCard: View {
    let mix: Mix
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            collage
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) {
                    Text(mix.title)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 6)
                        .padding(10)
                }
                .overlay(alignment: .bottomTrailing) {
                    if hovering {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.onAccent)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(theme.accent))
                            .shadow(radius: 4)
                            .padding(8)
                    }
                }
                .scaleEffect(hovering ? 1.02 : 1)
                .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 10, y: 4)
            Text(mix.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Text("\(mix.tracks.count) songs")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(width: 180, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering } }
        .onTapGesture { player.playShuffled(mix.tracks) }
        .contextMenu {
            Button("Shuffle") { player.playShuffled(mix.tracks) }
            Button("Play in Order") { player.play(mix.tracks) }
            Button("Add to Queue") { player.addToQueue(mix.tracks) }
        }
        .help("Click to shuffle \(mix.title)")
    }

    /// 2 x 2 covers; fewer covers repeat to fill the square.
    private var collage: some View {
        let ids = mix.artworkIds
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        ArtworkView(artworkId: ids.isEmpty ? nil : ids[(row * 2 + column) % ids.count],
                                    pixelSize: 200, cornerRadius: 0)
                            .frame(width: 90, height: 90)
                    }
                }
            }
        }
    }
}
