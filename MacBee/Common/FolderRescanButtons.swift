import MacBeeLibrary
import SwiftUI

/// "Rescan" beside a music folder: a quick check for new and changed files, or every file's tags read again.
struct MusicFolderRescanMenu: View {
    let library: MusicLibrary
    let folder: MusicLibrary.FolderState

    var body: some View {
        Menu("Rescan") {
            Button("Check for Changes") { library.scan(folderId: folder.id) }
            Button("Read All Tags Again") { library.scan(folderId: folder.id, readAll: true) }
        }
        .fixedSize()
        .disabled(folder.folder.isPaused || !folder.isOnline)
        .help("Scan just this folder: check for changes, or read every song's tags again (slower)")
    }
}

/// "Rescan" beside a video folder: looks through just that folder again.
struct VideoFolderRescanButton: View {
    let path: String
    @Environment(AppModel.self) private var app

    var body: some View {
        Button("Rescan") { Task { await app.refreshVideos(only: path) } }
            .disabled(app.videos.isScanning || app.preferences.pausedVideoFolders.contains(path))
            .help("Look through just this folder for new and removed videos")
    }
}
