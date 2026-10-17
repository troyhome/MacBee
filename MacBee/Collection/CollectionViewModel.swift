import MacBeeLibrary
import Observation

/// Favorite albums and songs for the Collection page.
@MainActor
@Observable
final class CollectionViewModel {
    private(set) var albums: [AlbumSummary] = []
    private(set) var tracks: [Track] = []
    private(set) var isLoaded = false
    private(set) var errorMessage: String?

    func load(from database: LibraryDatabase) async {
        do {
            async let albums = database.favoriteAlbums()
            async let tracks = database.favoriteTracks()
            (self.albums, self.tracks) = try await (albums, tracks)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }
}
