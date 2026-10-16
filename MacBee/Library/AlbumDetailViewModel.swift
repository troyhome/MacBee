import MacBeeLibrary
import Observation

@MainActor
@Observable
final class AlbumDetailViewModel {
    private(set) var tracks: [Track] = []

    func load(albumKey: String, from database: LibraryDatabase) async {
        tracks = (try? await database.tracks(inAlbum: albumKey)) ?? []
    }

    var genre: String? { tracks.lazy.compactMap(\.genre).first { !$0.isEmpty } }

    var hasMultipleDiscs: Bool { Set(tracks.compactMap(\.discNumber)).count > 1 }
    /// Compilations and albums with guests show each track's artist.
    var showsTrackArtists: Bool { Set(tracks.map(\.displayArtist)).count > 1 }
}
