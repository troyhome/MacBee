import SwiftUI

/// Right-click on Artists, Albums or Playlists in the sidebar: play something at random.
struct RandomPlayMenu: View {
    let item: SidebarItem
    @Environment(AppModel.self) private var app

    var body: some View {
        switch item {
        case .artists:
            Button { Task { await app.playRandomArtist() } } label: { Label("Play a Random Artist", systemImage: "dice") }
        case .albums:
            Button { Task { await app.playRandomAlbum() } } label: { Label("Play a Random Album", systemImage: "dice") }
        case .playlists:
            Button { Task { await app.playRandomPlaylist() } } label: { Label("Play a Random Playlist", systemImage: "dice") }
        default:
            EmptyView()
        }
    }
}
