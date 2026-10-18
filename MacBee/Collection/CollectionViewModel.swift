import MacBeeLibrary
import Observation

/// Favorite albums and songs for the Collection page.
@MainActor
@Observable
final class CollectionViewModel {
    private(set) var albums: [AlbumSummary] = []
    private(set) var tracks: [Track] = []
    /// Mixes kept with "Save to Saved Mixes".
    private(set) var savedMixes: [SavedMix] = []
    /// Compilation albums (Various Artists).
    private(set) var compilations: [AlbumSummary] = []
    private(set) var isLoaded = false
    private(set) var errorMessage: String?

    func deleteSavedMix(_ id: Int64, from database: LibraryDatabase) async {
        try? await database.deleteSavedMix(id: id)
        savedMixes.removeAll { $0.id == id }
    }

    func load(from database: LibraryDatabase) async {
        do {
            async let albums = database.favoriteAlbums()
            async let tracks = database.favoriteTracks()
            async let compilations = database.compilationAlbums()
            async let saved = database.savedMixes()
            (self.albums, self.tracks, self.compilations, self.savedMixes) = try await (albums, tracks, compilations, saved)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }
}
