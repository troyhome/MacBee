import SwiftUI

/// Favorite, elapsed time, position slider, total time, add-to-playlist.
struct ScrubberRow: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    /// Position while the user drags; the engine is only told when they let go.
    @State private var dragFraction: Double?

    var body: some View {
        let progress = player.engine.progress
        let duration = progress.duration ?? 0
        let isFavorite = player.currentTrack.map(player.isFavorite) ?? false

        HStack(spacing: 8) {
            BarIconButton(systemImage: isFavorite ? "heart.fill" : "heart",
                          help: isFavorite ? "Remove from favorites" : "Add to favorites",
                          isActive: isFavorite, size: 12) { player.toggleFavorite() }
                .disabled(player.currentTrack == nil)

            Text(Format.time(dragFraction.map { $0 * duration } ?? progress.elapsed))
                .frame(width: 44, alignment: .trailing)

            Slider(value: Binding(get: { dragFraction ?? progress.fraction },
                                  set: { dragFraction = $0 }),
                   in: 0...1) { editing in
                if !editing, let fraction = dragFraction {
                    player.seek(toFraction: fraction)
                    dragFraction = nil
                }
            }
            .controlSize(.mini)
            .disabled(progress.duration == nil)

            // Time left, like Apple Music.
            Text("-" + Format.time(max(0, duration - (dragFraction.map { $0 * duration } ?? progress.elapsed))))
                .frame(width: 44, alignment: .leading)

            Menu {
                if let track = player.currentTrack {
                    AddToPlaylistItems { [track] }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 26)
            .disabled(player.currentTrack == nil)
            .help("Add to playlist")
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(theme.textSecondary)
    }
}
