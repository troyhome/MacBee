import MacBeeLibrary
import SwiftUI

/// The Artists page: artist list on the left, the selected artist's albums and songs on the right.
struct ArtistsView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.theme) private var theme
    @State private var model = ArtistsViewModel()
    /// Remembered between launches.
    @AppStorage("selectedArtist") private var selectedKey = ""
    /// Width of the artist list, adjustable by dragging the divider.
    @AppStorage("artistColumnWidth") private var columnWidth = 300.0
    /// Text in the search box above the artist list.
    @State private var filter = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                FilterField(prompt: "Search artists", text: $filter)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                ArtistListColumn(artists: shownArtists, selectedKey: $selectedKey)
                    .overlay {
                        if shownArtists.isEmpty && !filter.isEmpty {
                            ContentUnavailableView.search(text: filter)
                        }
                    }
            }
            .frame(width: columnWidth)
            ColumnResizer(width: $columnWidth, range: 200...520, defaultWidth: 300)
            Group {
                if let artist = selectedArtist {
                    ArtistPageView(artist: artist) { other in selectedKey = other.artistKey }
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
        .task(id: "\(library.revision)-\(preferences.hideCompilationOnlyArtists)") {
            await model.load(from: library.database, hidingCompilationOnly: preferences.hideCompilationOnlyArtists)
            if selectedArtist == nil { selectedKey = model.artists.first?.artistKey ?? "" }
        }
    }

    /// Artists whose name contains the search text.
    private var shownArtists: [ArtistSummary] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.artists }
        return model.artists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selectedArtist: ArtistSummary? {
        model.artists.first { $0.artistKey == selectedKey }
    }
}
