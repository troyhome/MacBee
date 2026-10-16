import MacBeeLibrary
import Observation

/// Playlist Studio's library browser: the filters and the songs that match them.
@MainActor
@Observable
final class StudioViewModel {
    var filter = TrackFilter()
    private(set) var results: [Track] = []
    private(set) var genres: [String] = []
    private(set) var isLoaded = false

    static let resultLimit = 1000

    func search(in database: LibraryDatabase) async {
        let found = (try? await database.tracks(matching: filter, limit: Self.resultLimit)) ?? []
        guard !Task.isCancelled else { return } // a newer search replaced this one
        results = found
        isLoaded = true
    }

    func loadGenres(from database: LibraryDatabase) async {
        genres = (try? await database.genres()) ?? []
    }
}
