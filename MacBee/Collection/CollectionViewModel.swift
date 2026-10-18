import MacBeeLibrary
import Observation

/// Favorite albums and songs for the Collection page.
@MainActor
@Observable
final class CollectionViewModel {
    private(set) var albums: [AlbumSummary] = []
    private(set) var tracks: [Track] = []
    /// Compilation albums (Various Artists).
    private(set) var compilations: [AlbumSummary] = []
    private(set) var isLoaded = false
    private(set) var errorMessage: String?

    func load(from database: LibraryDatabase) async {
        do {
            async let albums = database.favoriteAlbums()
            async let tracks = database.favoriteTracks()
            async let compilations = database.compilationAlbums()
            (self.albums, self.tracks, self.compilations) = try await (albums, tracks, compilations)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }
}
