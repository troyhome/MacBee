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
                            .font(.system(size: 34, weight: .bold))
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
                            EpisodeRow(episode: episode) { app.playEpisode(episode, in: show, resume: true) }
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
    let onPlay: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Text("\(episode.number)")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(theme.textTertiary)
                    .opacity(hovering ? 0 : 1)
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accent)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: 30)
            Text(episode.title ?? "Episode \(episode.number)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer()
            if app.videos.watched.contains(episode.file.path) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.textTertiary)
                    .help("Watched")
            } else if app.videos.position(of: episode.file.path) > 0 {
                Text("In progress")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
            }
            if episode.file.is4K { VideoBadge(text: "4K") }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? theme.surface : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .onTapGesture(perform: onPlay)
        .help("Play \(episode.code)")
    }
}
