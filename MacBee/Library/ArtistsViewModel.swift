import MacBeeLibrary
import Observation

@MainActor
@Observable
final class ArtistsViewModel {
    private(set) var artists: [ArtistSummary] = []
    private(set) var isLoaded = false

    func load(from database: LibraryDatabase) async {
        artists = (try? await database.artists()) ?? []
        isLoaded = true
    }
}
