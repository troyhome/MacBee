import MacBeeLibrary
import Observation

/// Albums for the grid: the whole library, or one artist's.
@MainActor
@Observable
final class AlbumsViewModel {
    private(set) var albums: [AlbumSummary] = []
    private(set) var isLoaded = false
    private(set) var errorMessage: String?

    func load(from database: LibraryDatabase, sort: AlbumSort = .artist, artistKey: String? = nil) async {
        do {
            albums = try await database.albums(sortedBy: sort, artistKey: artistKey)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }
}
