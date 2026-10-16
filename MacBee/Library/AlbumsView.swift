import MacBeeLibrary
import SwiftUI

/// The Albums page: every album as a cover grid.
struct AlbumsView: View {
    @Environment(MusicLibrary.self) private var library
    @AppStorage("albumSort") private var sort: AlbumSortOption = .artist
    @State private var model = AlbumsViewModel()

    var body: some View {
        AlbumGrid(albums: model.albums)
            .overlay {
                if model.isLoaded && model.albums.isEmpty {
                    ContentUnavailableView("No albums yet", systemImage: "square.stack",
                                           description: Text(model.errorMessage ?? "Add a music folder on the Music page."))
                }
            }
            .navigationTitle("Albums")
            .navigationSubtitle(model.isLoaded ? "\(model.albums.count) albums" : "")
            .toolbar {
                ToolbarItem {
                    Picker("Sort by", selection: $sort) {
                        ForEach(AlbumSortOption.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .help("Sort albums")
                }
            }
            .task(id: "\(library.revision)-\(sort.rawValue)") {
                await model.load(from: library.database, sort: sort.librarySort)
            }
    }
}
