import AppKit
import MacBeeVideo
import SwiftUI

/// One card in Continue Watching: a movie, episode or music video stopped part-way through, or a show's
/// next episode after the last one was finished ("Up Next"), like the Apple TV app.
struct ContinueItem: Identifiable {
    enum Kind {
        case movie(Movie)
        case episode(Episode, Show)
        case musicVideo(MusicVideo)
    }

    let kind: Kind
    let file: VideoFile
    let date: Date
    let isUpNext: Bool

    var id: String { file.path }

    var title: String {
        switch kind {
        case let .movie(movie): movie.title
        case let .episode(_, show): show.title
        case let .musicVideo(video): video.title
        }
    }

    var subtitle: String {
        switch kind {
        case let .movie(movie): movie.year.map(String.init) ?? "Movie"
        case let .episode(episode, _):
            ["S\(episode.season), E\(episode.number)", episode.title].compactMap { $0 }.joined(separator: " · ")
        case let .musicVideo(video): video.folderName
        }
    }

    /// The movie or show page it belongs to.
    var page: VideoTitle? {
        switch kind {
        case let .movie(movie): .movie(movie)
        case let .episode(_, show): .show(show)
        case .musicVideo: nil
        }
    }
}

extension VideoLibrary {
    /// Everything to continue, most recently watched first.
    var continueItems: [ContinueItem] {
        var items: [ContinueItem] = []
        for movie in catalog.movies {
            if let file = movie.files.first(where: { positions[$0.path] != nil }) {
                items.append(ContinueItem(kind: .movie(movie), file: file,
                                          date: lastWatched[file.path] ?? lastPlayed[movie.id] ?? .distantPast, isUpNext: false))
            }
        }
        for show in catalog.shows {
            if let item = continueItem(for: show) { items.append(item) }
        }
        for video in catalog.musicVideos where positions[video.file.path] != nil {
            items.append(ContinueItem(kind: .musicVideo(video), file: video.file,
                                      date: lastWatched[video.file.path] ?? lastPlayed[video.id] ?? .distantPast, isUpNext: false))
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(30))
    }

    /// A show's card: the episode watched most recently if it's part-way through, otherwise the one after it.
    func continueItem(for show: Show) -> ContinueItem? {
        let all = show.seasons.flatMap(\.episodes)
        let fallback = lastPlayed[show.id] ?? .distantPast
        func when(_ e: Episode) -> Date? {
            lastWatched[e.file.path] ?? (positions[e.file.path] != nil ? fallback : nil)
        }
        guard let latest = all.compactMap({ e in when(e).map { (e, $0) } }).max(by: { $0.1 < $1.1 }) else { return nil }
        if positions[latest.0.file.path] != nil {
            return ContinueItem(kind: .episode(latest.0, show), file: latest.0.file, date: latest.1, isUpNext: false)
        }
        // Finished: offer the next episode not watched yet, unless that card was removed since.
        guard watched.contains(latest.0.file.path),
              upNextDismissed[show.id].map({ $0 < latest.1 }) ?? true,
              let index = all.firstIndex(where: { $0.id == latest.0.id }),
              let next = all[(index + 1)...].first(where: { !watched.contains($0.file.path) }) else { return nil }
        return ContinueItem(kind: .episode(next, show), file: next.file, date: latest.1, isUpNext: true)
    }
}

/// The Continue Watching row at the top of every Videos page.
struct ContinueWatchingRow: View {
    let items: [ContinueItem]
    let onOpenPage: (VideoTitle) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue Watching")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            HorizontalCarousel {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in ContinueCard(item: item, onOpenPage: onOpenPage) }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

/// A wide card with a still from the video, how far along it is and the time left. Click resumes.
private struct ContinueCard: View {
    let item: ContinueItem
    let onOpenPage: (VideoTitle) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { PosterImage(path: nil, title: item.title, previewFile: item.file) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) { footer }
                .overlay {
                    if hovering {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 6)
                    }
                }
                .scaleEffect(hovering ? 1.02 : 1)
                .shadow(color: .black.opacity(hovering ? 0.4 : 0.15), radius: hovering ? 10 : 4, y: 3)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Text(item.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 260)
        .contentShape(Rectangle())
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering } }
        .onTapGesture { play(resume: true) }
        .contextMenu {
            Button(item.isUpNext ? "Play" : "Resume") { play(resume: true) }
            if !item.isUpNext { Button("Play from Start") { play(resume: false) } }
            if let page = item.page {
                Button(page.isShow ? "Go to Show" : "Go to Movie") { onOpenPage(page) }
            }
            Divider()
            Button("Remove from Continue Watching") { app.videos.removeFromContinueWatching(item) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.file.url]) }
        }
        .help(item.isUpNext ? "Play the next episode" : "Resume where you stopped")
    }

    /// ▶, a progress bar and the time left, over a dark fade at the bottom of the still.
    private var footer: some View {
        let position = app.videos.position(of: item.file.path)
        let duration = app.videos.durations[item.file.path] ?? 0
        return HStack(spacing: 8) {
            Image(systemName: "play.fill").font(.system(size: 10))
            if item.isUpNext {
                Text("Up Next").font(.system(size: 11, weight: .semibold))
            } else {
                if duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.35))
                            Capsule().fill(.white).frame(width: geo.size.width * min(1, position / duration))
                        }
                    }
                    .frame(width: 44, height: 4)
                }
                Text(duration > 0 ? Self.left(duration - position) : "Resume")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
    }

    private func play(resume: Bool) {
        switch item.kind {
        case let .movie(movie): app.playMovie(movie, resume: resume)
        case let .episode(episode, show): app.playEpisode(episode, in: show, resume: resume)
        case let .musicVideo(video):
            if !resume { app.videos.savePosition(0, duration: 0, for: video.file.path) }
            app.playMusicVideo(video)
        }
    }

    /// "1h 13m left", "23m left".
    static func left(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
    }
}

extension VideoTitle {
    var isShow: Bool { if case .show = self { true } else { false } }
}
