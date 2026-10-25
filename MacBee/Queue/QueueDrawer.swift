import MacBeeLibrary
import SwiftUI

/// Slides in from the right, in three parts:
/// - History: songs played this session, newest at the bottom. Shows the last 3; scroll up for more.
/// - Now Playing: pinned in place, never scrolls.
/// - Up Next: drag to reorder, Delete or the x to remove, Clear. Fills the rest of the panel.
/// Double-click a song in History or Up Next to play it now.
struct QueueDrawer: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                BarIconButton(systemImage: "xmark", help: "Close queue", size: 12) { app.showQueue = false }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            QueueHistorySection()

            NowPlayingSection()

            UpNextSection()
                .frame(maxHeight: .infinity)
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(theme.sidebar)
        .overlay(alignment: .leading) { Rectangle().fill(theme.separator).frame(width: 1) }
        .shadow(color: .black.opacity(0.35), radius: 16, x: -4)
    }
}

/// Small grey heading used by the three parts of the drawer.
struct QueueSectionHeader: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
    }
}

/// Songs played this session, oldest at the top, newest just above Now Playing.
private struct QueueHistorySection: View {
    @Environment(PlayerViewModel.self) private var player

    /// Room for 3 rows; more scroll.
    private static let visibleRows = 3
    private static let rowHeight: CGFloat = 46

    var body: some View {
        // Stored newest first; shown oldest first so it reads like a timeline.
        let history = Array(player.queue.sessionHistory.reversed())
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                QueueSectionHeader(title: "History")
                    .padding(.horizontal, 16)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(history.enumerated()), id: \.offset) { index, track in
                                QueueRow(track: track)
                                    .frame(height: Self.rowHeight)
                                    .opacity(0.6)
                                    .padding(.horizontal, 16)
                                    .id(index)
                                    .onTapGesture(count: 2) { player.playNow(track) }
                                    .contextMenu {
                                        Button("Play") { player.playNow(track) }
                                        Button("Play Next") { player.playNext([track]) }
                                        Button("Add to Queue") { player.addToQueue([track]) }
                                    }
                            }
                        }
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: Self.rowHeight * CGFloat(min(history.count, Self.visibleRows)))
                    .onChange(of: history.count) { proxy.scrollTo(history.count - 1, anchor: .bottom) }
                }
            }
            .padding(.bottom, 8)
        }
    }
}

/// The current song, pinned between History and Up Next.
private struct NowPlayingSection: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            QueueSectionHeader(title: "Now Playing")
            if let current = player.currentTrack {
                QueueRow(track: current, isCurrent: true, isPlaying: player.isPlaying)
            } else {
                Text("Nothing is playing")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
    }
}

/// Upcoming songs. Drag to reorder, Delete or the x to remove, Clear empties it.
private struct UpNextSection: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var selection = Set<UUID>()

    var body: some View {
        let upNext = player.queue.upNext
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                QueueSectionHeader(title: "Up Next")
                Spacer()
                if !upNext.isEmpty {
                    Button("Clear") {
                        selection = []
                        player.clearUpNext()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if upNext.isEmpty {
                Text("Nothing up next. Right-click songs and choose Play Next or Add to Queue.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .padding(16)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(upNext) { item in
                        QueueRow(track: item.track, onRemove: { player.removeFromUpNext([item.id]) })
                            .tag(item.id)
                    }
                    .onMove { player.moveUpNext(fromOffsets: $0, toOffset: $1) }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if !ids.isEmpty {
                        Button("Play") { if let id = ids.first { player.playQueueItem(id) } }
                        Button("Remove from Queue") {
                            player.removeFromUpNext(ids)
                            selection.subtract(ids)
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first { player.playQueueItem(id) }
                }
                .onDeleteCommand {
                    player.removeFromUpNext(selection)
                    selection = []
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}
