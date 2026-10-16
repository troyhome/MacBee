import SwiftUI

/// Shuffle / previous / play-pause / next / repeat.
struct TransportControls: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 18) {
            BarIconButton(systemImage: "shuffle",
                          help: player.queue.isShuffled ? "Shuffle is on" : "Shuffle is off",
                          isActive: player.queue.isShuffled, size: 13) { player.toggleShuffle() }
            BarIconButton(systemImage: "backward.fill", help: "Previous (⌘←)", size: 15) { player.previous() }
                .disabled(player.currentTrack == nil)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.kind == .light ? Color.white : Color.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(theme.textPrimary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)
            .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
            BarIconButton(systemImage: "forward.fill", help: "Next (⌘→)", size: 15) { player.next() }
                .disabled(!player.queue.hasNext)
            BarIconButton(systemImage: player.queue.repeatMode == .one ? "repeat.1" : "repeat",
                          help: "Repeat: \(player.queue.repeatMode.title)",
                          isActive: player.queue.repeatMode != .off, size: 13) { player.cycleRepeat() }
        }
    }
}
