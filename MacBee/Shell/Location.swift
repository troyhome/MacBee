import MacBeeLibrary

/// Where you are in the window: a sidebar page, the open playlist (on the Playlists page),
/// and any album pages opened on top. The back arrow returns to earlier locations.
struct Location: Equatable {
    var page: SidebarItem
    var playlistId: Int64?
    var albums: [AlbumSummary] = []
}
