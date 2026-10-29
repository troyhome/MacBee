import MacBeeVideo
import SwiftUI

/// One TV show: poster, title, Play (continues where you left off), the seasons as tabs and the episode list.
struct ShowDetailView: View {
    let show: Show
    let onBack: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var seasonNumber: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom, spacing: 28) {
                    Color.clear
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .overlay { PosterImage(path: show.posterPath, title: show.title, maxPixels: 700, previewFile: show.firstEpisode?.file) }
                        .frame(width: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(show.title)
                            .font(.mbDetailTitle)
                            .foregroundStyle(theme.textPrimary)
                        Text(details)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                        if let summary = show.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(5)
                                .frame(maxWidth: 620, alignment: .leading)
                        }
                        HStack(spacing: 12) {
                            if let next = app.videos.nextEpisode(in: show) {
                                let resume = app.videos.position(of: next.file.path) > 0
                                VideoPlayButton(title: "\(resume ? "Resume" : "Play") \(next.code)") {
                                    app.playEpisode(next, in: show, resume: true)
                                }
                            }
                            VideoLikeButton(id: show.id, diameter: 40)
                        }
                        .padding(.top, 8)
                    }
                }
                if show.seasons.count > 1 {
                    // Every season as a tab along the top, like the TV app.
                    HorizontalCarousel {
                        HStack(spacing: 8) {
                            ForEach(show.seasons) { season in
                                let selected = season.number == selectedSeason?.number
                                Button("Season \(season.number)") { seasonNumber = season.number }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? theme.onAccent : theme.textPrimary)
                                    .padding(.horizontal, 14)
                                    .frame(height: 30)
                                    .background(Capsule().fill(selected ? theme.accent : theme.surface))
                                    .contentShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                if let season = selectedSeason {
                    LazyVStack(spacing: 2) {
                        ForEach(season.episodes) { episode in
                            EpisodeRow(episode: episode, show: show, season: season) {
                                app.playEpisode(episode, in: show, resume: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 70)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            PosterImage(path: show.posterPath, title: "", maxPixels: 300)
                .blur(radius: 60)
                .opacity(0.35)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            CircleButton(systemImage: "chevron.left", help: "Back", tinted: false, action: onBack)
                .padding(.leading, 20)
                .padding(.top, 14)
        }
        .navigationTitle(show.title)
        .onAppear {
            // Open on the season you're up to.
            if seasonNumber == nil { seasonNumber = app.videos.nextEpisode(in: show)?.season }
        }
    }

    private var selectedSeason: Season? {
        show.seasons.first { $0.number == seasonNumber } ?? show.seasons.first
    }

    private var details: String {
        let seasons = show.seasons.count == 1 ? "1 season" : "\(show.seasons.count) seasons"
        let episodes = "\(show.episodeCount) episodes"
        return [show.year.map(String.init), seasons, episodes, show.genres.isEmpty ? nil : show.genres.joined(separator: ", ")]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let show: Show
    let season: Season
    let onPlay: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let isWatched = app.videos.watched.contains(episode.file.path)
        let position = app.videos.position(of: episode.file.path)
        HStack(spacing: 14) {
            Text("\(episode.number)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
                .frame(width: 24)
            // A small still from the episode, with how far you got.
            Color.clear
                .frame(width: 112, height: 63)
                .overlay { PosterImage(path: nil, title: "", maxPixels: 260, previewFile: episode.file, titlesStill: false) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if hovering {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                }
                .overlay(alignment: .bottom) {
                    if position > 0, let duration = app.videos.durations[episode.file.path], duration > 0 {
                        GeometryReader { geometry in
                            Capsule().fill(theme.accent)
                                .frame(width: geometry.size.width * min(1, position / duration), height: 3)
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 5)
                    }
                }
                .opacity(isWatched && !hovering ? 0.6 : 1)
            Text(episode.title ?? "Episode \(episode.number)")
                .font(.mbRowTitle)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
            Spacer()
            if !isWatched && position > 0 {
                Text("In progress")
                    .font(.mbCaption)
                    .foregroundStyle(theme.accent)
            }
            if episode.file.is4K { VideoBadge(text: "4K") }
            Button {
                app.videos.setWatched(!isWatched, paths: [episode.file.path])
            } label: {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isWatched ? theme.accent : theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(isWatched ? "Watched. Click to mark as not watched." : "Mark as watched")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? theme.surface : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onPlay)
        .help("Play \(episode.code)")
        .contextMenu {
            Button("Play") { onPlay() }
            if position > 0 { Button("Play from Start") { app.playEpisode(episode, in: show, resume: false) } }
            Divider()
            Button(isWatched ? "Mark as Not Watched" : "Mark as Watched") {
                app.videos.setWatched(!isWatched, paths: [episode.file.path])
            }
            Button("Mark Earlier Episodes as Watched") {
                let all = show.seasons.flatMap(\.episodes)
                let earlier = all.prefix { $0.id != episode.id }.map(\.file.path)
                app.videos.setWatched(true, paths: earlier)
            }
            Button("Mark Season \(season.number) as Watched") {
                app.videos.setWatched(true, paths: season.episodes.map(\.file.path))
            }
            Button("Mark Season \(season.number) as Not Watched") {
                app.videos.setWatched(false, paths: season.episodes.map(\.file.path))
            }
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([episode.file.url]) }
        }
    }
}
