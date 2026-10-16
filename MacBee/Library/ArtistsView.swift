import MacBeeLibrary
import SwiftUI

/// The Artists page: artist list on the left, the selected artist's albums and songs on the right.
struct ArtistsView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var model = ArtistsViewModel()
    /// Remembered between launches.
    @AppStorage("selectedArtist") private var selectedKey = ""
    /// Width of the artist list, adjustable by dragging the divider.
    @AppStorage("artistColumnWidth") private var columnWidth = 300.0

    var body: some View {
        HStack(spacing: 0) {
            ArtistListColumn(artists: model.artists, selectedKey: $selectedKey)
                .frame(width: columnWidth)
            ColumnResizer(width: $columnWidth, range: 200...520)
            Group {
                if let artist = selectedArtist {
                    ArtistPageView(artist: artist)
                } else if model.isLoaded {
                    ContentUnavailableView("No artists yet", systemImage: "music.mic",
                                           description: Text("Add a music folder on the Music page."))
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Artists")
        .navigationSubtitle(model.isLoaded ? "\(model.artists.count) artists" : "")
        .task(id: library.revision) {
            await model.load(from: library.database)
            if selectedArtist == nil { selectedKey = model.artists.first?.artistKey ?? "" }
        }
    }

    private var selectedArtist: ArtistSummary? {
        model.artists.first { $0.artistKey == selectedKey }
    }
}
