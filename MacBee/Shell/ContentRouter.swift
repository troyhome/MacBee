import MacBeeLibrary
import SwiftUI

/// Shows the page for the selected sidebar item. Library pages get their own navigation stack.
/// Open album pages live in AppModel's location, so the back arrow can return to them from anywhere.
struct ContentRouter: View {
    let selection: SidebarItem
    @Environment(AppModel.self) private var app

    var body: some View {
        page
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
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
                if let id = app.selectedPlaylistId {
                    PlaylistDetailView(playlistId: id)
                } else {
                    AllPlaylistsView()
                }
            }
        case .tags:
            PlaceholderView(title: "Tags", systemImage: "tag",
                            message: "Browsing by genre and other tags comes later.")
        case .playlistStudio:
            stack { PlaylistStudioView() }
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
