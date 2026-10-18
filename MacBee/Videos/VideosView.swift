import MacBeeLibrary
import SwiftUI

/// The Videos page: music videos found in the music folders, with a search box. Click one to play it.
/// Inside Collection it shows only the videos you've liked.
struct VideosView: View {
    /// Shown inside the Collection page (liked videos only), which has its own title.
    var embedded = false
    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var searchText = ""

    var body: some View {
        VideosGrid(videos: shown)
            .safeAreaInset(edge: .top, spacing: 0) {
                if embedded { searchRow.padding(.horizontal, 28).padding(.vertical, 6) } else { header }
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
            searchRow
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background(theme.background)
    }

    private var shown: [VideoItem] {
        app.videos.videos(matching: searchText, likedOnly: embedded)
    }

    private var searchRow: some View {
        FilterField(prompt: "Search videos", text: $searchText)
            .frame(width: 240)
    }

    @ViewBuilder
    private var emptyState: some View {
        if app.videos.hasSearched && shown.isEmpty {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if embedded {
                ContentUnavailableView("No liked videos yet", systemImage: "heart",
                                       description: Text("Click the heart on a video in Videos to add it here."))
            } else {
                ContentUnavailableView("No music videos found", systemImage: "play.rectangle",
                                       description: Text("MacBee looks for MP4, M4V and MOV files inside your music folders."))
            }
        }
    }
}

/// Video thumbnails in a grid.
struct VideosGrid: View {
    let videos: [VideoItem]

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(videos) { VideoTile(video: $0) }
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
            .overlay(alignment: .topTrailing) {
                if hovering || app.videos.isLiked(video) {
                    VideoLikeButton(video: video, diameter: 28)
                        .padding(6)
                }
            }
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

/// Heart that likes or unlikes a video. Liked videos show in Collection > Videos.
struct VideoLikeButton: View {
    let video: VideoItem
    var diameter: CGFloat = 28
    @Environment(AppModel.self) private var app

    var body: some View {
        let liked = app.videos.isLiked(video)
        CircleButton(systemImage: liked ? "heart.fill" : "heart",
                     help: liked ? "Unlike (removes it from Collection)" : "Like (adds it to Collection)",
                     diameter: diameter) { app.videos.toggleLike(video) }
    }
}
