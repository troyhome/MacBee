import MacBeeLibrary
import Observation

/// One artist's albums, newest first, each with its tracks.
@MainActor
@Observable
final class ArtistPageViewModel {
    struct AlbumSection: Identifiable {
        let album: AlbumSummary
        let tracks: [Track]
        var id: String { album.albumKey }
        var genre: String? { tracks.lazy.compactMap(\.genre).first { !$0.isEmpty } }
        /// Compilations and albums with guests show each track's artist.
        var showsTrackArtists: Bool { Set(tracks.map(\.displayArtist)).count > 1 }
        var hasMultipleDiscs: Bool { Set(tracks.compactMap(\.discNumber)).count > 1 }
    }

    private(set) var sections: [AlbumSection] = []
    private var loadedKey: String?

    var allTracks: [Track] { sections.flatMap(\.tracks) }

    func load(artistKey: String, from database: LibraryDatabase) async {
        // Don't show the previous artist's albums under the new name.
        if loadedKey != artistKey { sections = [] }
        do {
            var result: [AlbumSection] = []
            for album in try await database.albums(sortedBy: .year, artistKey: artistKey) {
                result.append(AlbumSection(album: album, tracks: try await database.tracks(inAlbum: album.albumKey)))
            }
            guard !Task.isCancelled else { return }
            sections = result
            loadedKey = artistKey
        } catch {
            sections = []
        }
    }
}
