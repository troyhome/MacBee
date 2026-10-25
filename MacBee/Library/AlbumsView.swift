import MacBeeLibrary
import SwiftUI

/// The Albums page: every album as a cover grid.
struct AlbumsView: View {
    @Environment(MusicLibrary.self) private var library
    @AppStorage("albumSort") private var sort: AlbumSortOption = .artist
    @AppStorage("albumLayout") private var layout: AlbumLayout = .grid
    @State private var model = AlbumsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Albums", subtitle: model.isLoaded ? "\(model.albums.count) albums" : nil) {
                Picker("Layout", selection: $layout) {
                    ForEach(AlbumLayout.allCases) { Label($0.title, systemImage: $0.systemImage).labelStyle(.iconOnly).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Show albums as a grid or a list")
                Picker("Sort by", selection: $sort) {
                    ForEach(AlbumSortOption.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help("Sort albums")
            }
            AlbumGrid(albums: model.albums, layout: layout, indexName: indexName)
                .overlay {
                    if model.isLoaded && model.albums.isEmpty {
                        ContentUnavailableView("No albums yet", systemImage: "square.stack",
                                               description: Text(model.errorMessage ?? "Add a music folder in Settings > Library."))
                    }
                }
        }
            .navigationTitle("Albums")
            .task(id: "\(library.revision)-\(sort.rawValue)") {
                await model.load(from: library.database, sort: sort.librarySort)
            }
    }

    /// The A–Z strip follows the sort: artist names, or album titles. Year and Recently Added have no strip.
    private var indexName: ((AlbumSummary) -> String)? {
        switch sort {
        case .artist: { $0.artist }
        case .title: { $0.title }
        case .year, .recentlyAdded: nil
        }
    }
}
