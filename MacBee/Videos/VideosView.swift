import AppKit
import MacBeeLibrary
import MacBeeVideo
import SwiftUI

/// The Videos page, laid out like the Apple TV app: sections on the left (Recently Played, Movies, TV Shows,
/// Music Videos, Genres), posters on the right, and a page for each movie or show.
/// Inside Collection (`embedded`) it shows only liked videos, without the sections.
struct VideosView: View {
    var embedded = false

    @Environment(AppModel.self) private var app
    @Environment(MusicLibrary.self) private var library
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.theme) private var theme
    @AppStorage("videoCategory") private var category: VideoCategory = .movies
    @State private var genre: String?
    @State private var searchText = ""
    @State private var open: VideoTitle?
    @State private var sort = VideoSort()

    var body: some View {
        HStack(spacing: 0) {
            if !embedded && open == nil {
                VideoSidebar(category: $category, catalog: app.videos.catalog)
                Rectangle().fill(theme.separator).frame(width: 1)
            }
            Group {
                if let open {
                    detail(for: open)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if !embedded { header }
                        browse
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(embedded ? "Collections" : "Videos")
        .onAppear { sort = VideoSort.load(for: shownCategory) }
        .onChange(of: shownCategory) { _, new in sort = VideoSort.load(for: new) }
        .onChange(of: sort) { _, new in new.save(for: shownCategory) }
        .task(id: "\(library.revision)-\(preferences.videoFolders.count)") { await app.refreshVideosIfStale() }
    }

    // MARK: - Header and lists

    private var header: some View {
        PageHeader(title: shownCategory.title,
                   subtitle: app.videos.isScanning ? "Looking for videos…" : nil,
                   showsDivider: true) {
            Button {
                Task { await app.refreshVideos() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(app.videos.isScanning)
            .help("Look for new videos")
            if shownCategory == .shows {
                @Bindable var preferences = preferences
                Toggle("Continuous Play", isOn: $preferences.continuousPlayEpisodes)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Play the next episode automatically when one ends")
            }
            HeaderDivider()
            if Self.sortable.contains(shownCategory) {
                VideoSortMenu(category: shownCategory, sort: $sort)
            }
            FilterField(prompt: "Search videos", text: $searchText)
                .frame(minWidth: 120, maxWidth: 220)
        }
    }

    private var shownCategory: VideoCategory {
        if embedded { return .liked }
        return VideoCategory.sidebar.contains(category) ? category : .movies
    }


    private static let sortable: Set<VideoCategory> = [.movies, .shows, .musicVideos]

    private var titles: [VideoTitle] {
        let titles = app.videos.titles(in: shownCategory, genre: genre ?? app.videos.catalog.genres.first,
                                       matching: searchText)
        return Self.sortable.contains(shownCategory) ? sort.apply(to: titles) : titles
    }

    @ViewBuilder
    private var browse: some View {
        if preferences.videoFolders.isEmpty && app.videos.catalog.isEmpty && !embedded {
            ContentUnavailableView {
                Label("No video folders yet", systemImage: "film.stack")
            } description: {
                Text("Choose the folder or drive with your movies and TV shows. MacBee plays MKV, MP4, 4K and HDR.")
            } actions: {
                Button("Add Video Folder…") { addVideoFolder() }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if embedded {
                        FilterField(prompt: "Search liked videos", text: $searchText)
                            .frame(width: 240)
                    }
                    // Like the Apple TV app: what you're in the middle of, on every Videos page.
                    let continuing = embedded || !searchText.isEmpty ? [] : app.videos.continueItems
                    if !continuing.isEmpty {
                        ContinueWatchingRow(items: continuing) { open = $0 }
                        rowTitle(shownCategory == .movies ? "All Movies" : shownCategory == .shows ? "All Shows"
                                 : shownCategory.title)
                    }
                    if shownCategory == .genres { genrePicker }
                    VideoPosterGrid(titles: titles) { openOrPlay($0) }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay { emptyState }
        }
    }

    private func rowTitle(_ text: String) -> some View {
        Text(text)
            .font(.mbSection)
            .foregroundStyle(theme.textPrimary)
    }

    private var genrePicker: some View {
        let genres = app.videos.catalog.genres
        let selected = genre ?? genres.first
        return HorizontalCarousel {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { name in
                    Button(name) { genre = name }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(name == selected ? theme.onAccent : theme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(name == selected ? theme.accent : theme.surface))
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if titles.isEmpty && !app.videos.isScanning {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if embedded {
                ContentUnavailableView("No liked videos yet", systemImage: "heart",
                                       description: Text("Click the heart on a movie, show or music video to add it here."))
            } else if shownCategory == .genres {
                ContentUnavailableView("No genres found", systemImage: "theatermasks",
                                       description: Text("Genres come from .nfo files next to your videos, or from Plex."))
            } else if shownCategory == .recentlyPlayed {
                ContentUnavailableView("Nothing played yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Movies, shows and music videos you play show up here."))
            } else if shownCategory == .musicVideos {
                ContentUnavailableView("No music videos found", systemImage: "music.note.tv",
                                       description: Text("MacBee looks for videos in your music folders."))
            } else if preferences.videoFolders.isEmpty {
                // Music videos from the music folders can fill the catalog before any video folder is added.
                ContentUnavailableView {
                    Label("No video folders yet", systemImage: "film.stack")
                } description: {
                    Text("Choose the folder or drive with your movies and TV shows.")
                } actions: {
                    Button("Add Video Folder…") { addVideoFolder() }
                }
            } else {
                ContentUnavailableView {
                    Label("Nothing here yet", systemImage: shownCategory.systemImage)
                } actions: {
                    Button("Add Video Folder…") { addVideoFolder() }
                }
            }
        }
    }

    // MARK: - Opening

    private func openOrPlay(_ title: VideoTitle) {
        if case let .musicVideo(video) = title {
            app.playMusicVideo(video)
        } else {
            open = title
        }
    }

    @ViewBuilder
    private func detail(for title: VideoTitle) -> some View {
        switch title {
        case let .movie(movie): MovieDetailView(movie: movie) { open = nil }
        case let .show(show): ShowDetailView(show: show) { open = nil }
        case .musicVideo: EmptyView()
        }
    }

    private func addVideoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        panel.message = "Choose a folder with movies and TV shows"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        FolderAccess.shared.remember(url)
        preferences.addVideoFolder(url.path)
        Task { await app.refreshVideos() }
    }
}

/// The section list on the left of the Videos page.
private struct VideoSidebar: View {
    @Binding var category: VideoCategory
    let catalog: VideoCatalog
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LIBRARY")
                .font(.mbLabel)
                .tracking(0.8)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            ForEach(shown) { item in
                Button {
                    category = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.systemImage)
                            .frame(width: 18)
                            .foregroundStyle(item == category ? theme.accent : theme.textSecondary)
                        Text(item.title)
                            .foregroundStyle(item == category ? theme.textPrimary : theme.textSecondary)
                            .fontWeight(item == category ? .semibold : .regular)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(item == category ? theme.elevated : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 28)
        .padding(.horizontal, 8)
        .frame(width: 180)
    }

    private var shown: [VideoCategory] { VideoCategory.sidebar }
}
