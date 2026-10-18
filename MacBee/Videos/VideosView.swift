import MacBeeLibrary
import SwiftUI

/// The Videos page: music videos found in the music folders. Click one to play it.
struct VideosView: View {
    /// Shown inside the Collection page, which has its own title.
    var embedded = false
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme

    var body: some View {
        VideosGrid()
            .safeAreaInset(edge: .top, spacing: 0) {
                if !embedded { header }
            }
            .overlay { emptyState }
            .navigationTitle(embedded ? "Collection" : "Videos")
            .task(id: library.revision) {
                await app.videos.refresh(folders: library.folders.filter(\.isOnline).map(\.folder.url))
            }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if app.canGoBack {
                CircleButton(systemImage: "chevron.left", help: "Back", tinted: false) { app.goBack() }
            }
            Text("Videos")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if app.videos.isSearching {
                Text("Looking for videos…")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background(theme.background)
    }

    @ViewBuilder
    private var emptyState: some View {
        if app.videos.hasSearched && app.videos.videos.isEmpty {
            ContentUnavailableView("No music videos found", systemImage: "play.rectangle",
                                   description: Text("MacBee looks for MP4, M4V and MOV files inside your music folders."))
        }
    }
}

/// Video thumbnails in a grid.
struct VideosGrid: View {
    @Environment(AppModel.self) private var app

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(app.videos.videos) { VideoTile(video: $0) }
            }
            .padding(24)
        }
    }
}

private struct VideoTile: View {
    let video: VideoItem
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Rectangle().fill(theme.surface)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                }
                if hovering {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(theme.accent))
                        .shadow(radius: 4)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(video.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
            Text(video.folderName)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.playVideo(video) }
        .help("Play \(video.title)")
        .task(id: video.url) { thumbnail = await app.videos.thumbnail(for: video) }
    }
}
