import MacBeeVideo
import SwiftUI

/// A poster with the title and year under it. Click opens the movie or show; music videos play right away.
struct VideoPosterCard: View {
    let title: VideoTitle
    let onOpen: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(path: title.posterPath, title: title.title)
                .aspectRatio(isWide ? 16 / 9 : 2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) { qualityBadges.padding(6) }
                .overlay(alignment: .topTrailing) {
                    if hovering || app.videos.isLiked(title.id) {
                        VideoLikeButton(id: title.id, diameter: 26).padding(6)
                    }
                }
                .overlay(alignment: .bottom) { progressBar }
                .scaleEffect(hovering ? 1.02 : 1)
                .shadow(color: .black.opacity(hovering ? 0.4 : 0.15), radius: hovering ? 10 : 4, y: 3)
            Text(title.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Text(title.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering } }
        .onTapGesture(perform: onOpen)
        .help(title.title)
    }

    private var isWide: Bool {
        if case .musicVideo = title { return true }
        return false
    }

    @ViewBuilder
    private var qualityBadges: some View {
        HStack(spacing: 4) {
            if title.is4K { VideoBadge(text: "4K") }
            if title.isHDR { VideoBadge(text: "HDR") }
        }
    }

    /// How far a movie in progress has been watched.
    @ViewBuilder
    private var progressBar: some View {
        if case let .movie(movie) = title, let file = movie.file, app.videos.position(of: file.path) > 0 {
            Capsule()
                .fill(theme.accent)
                .frame(height: 4)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }
}

struct VideoBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.65)))
    }
}

/// Heart that likes or unlikes a movie, show or music video. Liked ones show in Collection > Videos.
struct VideoLikeButton: View {
    let id: String
    var diameter: CGFloat = 28
    @Environment(AppModel.self) private var app

    var body: some View {
        let liked = app.videos.isLiked(id)
        CircleButton(systemImage: liked ? "heart.fill" : "heart",
                     help: liked ? "Unlike (removes it from Collection)" : "Like (adds it to Collection)",
                     diameter: diameter) { app.videos.toggleLike(id) }
    }
}

/// Posters in a grid. Movies and shows use tall posters, music videos wide ones.
struct VideoPosterGrid: View {
    let titles: [VideoTitle]
    let onOpen: (VideoTitle) -> Void

    var body: some View {
        let wide = titles.allSatisfy { if case .musicVideo = $0 { true } else { false } }
        let columns = [GridItem(.adaptive(minimum: wide ? 220 : 140, maximum: wide ? 300 : 190), spacing: 20, alignment: .top)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(titles) { title in
                VideoPosterCard(title: title) { onOpen(title) }
            }
        }
    }
}
