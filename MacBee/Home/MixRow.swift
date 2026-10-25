import MacBeeLibrary
import SwiftUI

/// Suggested mixes as cards with a four-cover collage. Click shuffles the mix; the bookmark (or right-click)
/// saves it to Collections > Saved Mixes.
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

struct MixCard: View {
    let mix: Mix
    /// For saved mixes: removes it from Saved Mixes (instead of offering to save it).
    var onDelete: (() -> Void)?
    @Environment(PlayerViewModel.self) private var player
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var hovering = false
    @State private var saved = false

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
                .overlay(alignment: .topTrailing) {
                    if hovering && onDelete == nil {
                        Button(action: save) {
                            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .help(saved ? "Saved to Saved Mixes" : "Save to Saved Mixes")
                    }
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
            Button("Play") { player.play(mix.tracks) }
            Button("Shuffle") { player.playShuffled(mix.tracks) }
            Button("Play Next") { player.playNext(mix.tracks) }
            Button("Add to Queue") { player.addToQueue(mix.tracks) }
            Divider()
            AddToPlaylistMenu { mix.tracks }
            Divider()
            if let onDelete {
                Button("Remove from Saved Mixes", action: onDelete)
            } else {
                Button("Save to Saved Mixes", action: save)
            }
        }
        .help("Click to shuffle \(mix.title)")
    }

    /// Keeps this mix's songs as they are now, in Collections > Saved Mixes.
    private func save() {
        guard !saved else { return }
        saved = true
        let ids = mix.tracks.compactMap(\.id)
        Task { try? await library.database.saveMix(title: mix.title, subtitle: mix.subtitle, trackIds: ids) }
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
