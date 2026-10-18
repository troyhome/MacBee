import MacBeeLibrary
import SwiftUI

/// Shows the page for the selected sidebar item. Library pages get their own navigation stack.
/// Open album pages live in AppModel's location, so the back arrow can return to them from anywhere.
struct ContentRouter: View {
    let selection: SidebarItem
    @Environment(AppModel.self) private var app
    /// Width of Track Studio when it sits beside a library page.
    @AppStorage("trackStudioWidth") private var trackStudioWidth = 620.0

    var body: some View {
        page(for: selection)
    }

    @ViewBuilder
    private func page(for item: SidebarItem) -> some View {
        switch item {
        case .search:
            stack { SearchView() }
        case .home, .playingFrom: // Playing From is a shortcut, not a page of its own
            stack { HomeView() }
        case .videos:
            stack { VideosView() }
        case .collection:
            stack { CollectionView() }
        case .artists:
            stack { ArtistsView() }
        case .albums:
            stack { AlbumsView() }
        case .playlists:
            stack {
                if let smart = SmartPlaylist(playlistId: app.selectedPlaylistId) {
                    SmartPlaylistView(smart: smart)
                } else if let id = app.selectedPlaylistId {
                    PlaylistDetailView(playlistId: id)
                } else {
                    AllPlaylistsView()
                }
            }
        case .tags:
            if let browse = app.trackStudioBrowse {
                // Track Studio stays open on the right while a library page is browsed on the left.
                HStack(spacing: 0) {
                    libraryPage(browse)
                        .frame(minWidth: 320, maxWidth: .infinity)
                    ColumnResizer(width: $trackStudioWidth, range: 420...1100, resizesLeftColumn: false, defaultWidth: 620)
                    TagsView()
                        .frame(width: trackStudioWidth)
                }
            } else {
                stack { TagsView() }
            }
        case .playlistStudio:
            stack { PlaylistStudioView() }
        }
    }

    /// The library pages that can sit beside Track Studio.
    @ViewBuilder
    private func libraryPage(_ item: SidebarItem) -> some View {
        switch item {
        case .search: stack { SearchView() }
        case .collection: stack { CollectionView() }
        case .artists: stack { ArtistsView() }
        case .albums: stack { AlbumsView() }
        default: stack { HomeView() }
        }
    }

    private func stack<Root: View>(@ViewBuilder _ root: () -> Root) -> some View {
        NavigationStack(path: Binding(get: { app.albumPath }, set: { app.albumPath = $0 })) {
            root()
                .navigationDestination(for: AlbumSummary.self) { AlbumDetailView(album: $0) }
        }
        .environment(\.libraryNavigation, LibraryNavigation(openAlbum: { app.openAlbum($0) }))
    }
}

/// Lets grids and lists open an album page.
struct LibraryNavigation {
    var openAlbum: (AlbumSummary) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var libraryNavigation = LibraryNavigation()
}
