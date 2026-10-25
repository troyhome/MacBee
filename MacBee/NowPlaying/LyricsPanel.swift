import MacBeeLibrary
import SwiftUI

/// Lyrics (Now Playing and the lyrics panel): the text embedded in the song's tags, or an .lrc file next to it
/// (including ones MacBee found online, see `LyricsService`).
/// They follow the song: the current line is highlighted and kept in view; click a line to jump there.
/// Lyrics without timings are spread evenly over the song, so they still move along with it (roughly).
struct LyricsPanel: View {
    let track: Track
    @Environment(PlayerViewModel.self) private var player
    @Environment(AppModel.self) private var app
    @State private var lyrics: Lyrics?
    @State private var loadedPath: String?

    private var duration: Double { player.engine.progress.duration ?? track.duration }

    var body: some View {
        Group {
            switch lyrics {
            case let .timed(lines):
                TimedLyricsView(lines: lines)
            case let .plain(text):
                VStack(alignment: .leading, spacing: 4) {
                    TimedLyricsView(lines: LyricsReader.estimatedTiming(text, duration: duration))
                    Text("These lyrics have no timings, so their pace is estimated.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            case nil:
                HStack(spacing: 8) {
                    Image(systemName: "quote.bubble")
                    Text(app.lyrics.searchingPath == track.path ? "Looking for lyrics online…"
                         : loadedPath == track.path ? "No lyrics for this song." : "")
                }
                .font(.mbSecondary)
                .foregroundStyle(.white.opacity(0.45))
            }
        }
        .task(id: "\(track.path)-\(app.lyrics.savedCount)") {
            let song = track
            lyrics = await Task.detached(priority: .userInitiated) { LyricsReader.lyrics(for: song) }.value
            loadedPath = song.path
        }
    }
}

private struct TimedLyricsView: View {
    let lines: [Lyrics.TimedLine]
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let current = Lyrics.currentLine(in: lines, at: player.engine.progress.elapsed)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: index == current ? 20 : 17, weight: .bold))
                            .foregroundStyle(index == current ? .white : .white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { player.engine.seek(to: line.time) }
                            .id(index)
                    }
                }
                .padding(.vertical, 40)
                .animation(.easeOut(duration: 0.2), value: current)
            }
            .onChange(of: current) { _, line in
                guard let line else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(line, anchor: .center) }
            }
        }
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
    }
}
