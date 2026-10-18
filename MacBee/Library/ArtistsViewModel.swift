import MacBeeLibrary
import Observation

@MainActor
@Observable
final class ArtistsViewModel {
    private(set) var artists: [ArtistSummary] = []
    private(set) var isLoaded = false

    func load(from database: LibraryDatabase, hidingCompilationOnly: Bool = false) async {
        artists = (try? await database.artists(hidingCompilationOnly: hidingCompilationOnly)) ?? []
        isLoaded = true
    }
}
