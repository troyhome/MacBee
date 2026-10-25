import MacBeeVideo
import SwiftUI

/// One movie: big poster, title, year, quality, genres, Play / Resume, and the copies on disk.
struct MovieDetailView: View {
    let movie: Movie
    let onBack: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay { PosterImage(path: movie.posterPath, title: movie.title, maxPixels: 900, previewFile: movie.file) }
                    .frame(width: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 10) {
                    Text(movie.title)
                        .font(.mbDetailTitle)
                        .foregroundStyle(theme.textPrimary)
                    HStack(spacing: 8) {
                        if let year = movie.year {
                            Text(String(year)).foregroundStyle(theme.textSecondary)
                        }
                        if movie.is4K { VideoBadge(text: "4K") }
                        if movie.isHDR { VideoBadge(text: "HDR") }
                        if !movie.genres.isEmpty {
                            Text(movie.genres.joined(separator: ", ")).foregroundStyle(theme.textSecondary)
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    if let summary = movie.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: 620, alignment: .leading)
                            .padding(.top, 4)
                    }
                    HStack(spacing: 12) {
                        if let file = movie.file {
                            let position = app.videos.position(of: file.path)
                            VideoPlayButton(title: position > 0 ? "Resume" : "Play") { app.playMovie(movie, resume: true) }
                            if position > 0 {
                                Button("Play from Start") { app.playMovie(movie, resume: false) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        VideoLikeButton(id: movie.id, diameter: 40)
                    }
                    .padding(.top, 10)
                    if movie.files.count > 1 {
                        Text("Copies")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.top, 18)
                        ForEach(movie.files, id: \.path) { file in
                            Button {
                                app.playVideoFile(file, title: movie.title, subtitle: movie.year.map(String.init) ?? "", likeId: movie.id)
                            } label: {
                                Label(fileLabel(file), systemImage: "play.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.textPrimary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.top, 70)
            .padding(.bottom, 32)
        }
        .background {
            PosterImage(path: movie.posterPath, title: "", maxPixels: 300)
                .blur(radius: 60)
                .opacity(0.35)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            CircleButton(systemImage: "chevron.left", help: "Back", tinted: false, action: onBack)
                .padding(.leading, 20)
                .padding(.top, 14)
        }
        .navigationTitle(movie.title)
    }

    private func fileLabel(_ file: VideoFile) -> String {
        let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        let quality = [file.is4K ? "4K" : nil, file.isHDR ? "HDR" : nil].compactMap { $0 }.joined(separator: " ")
        return [URL(fileURLWithPath: file.path).pathExtension.uppercased(), quality, size]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The big accent Play button on movie and show pages.
struct VideoPlayButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 30)
                .frame(height: 40)
                .background(Capsule().fill(theme.accent.opacity(hovering ? 0.85 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
