import MacBeeLibrary
import Observation

/// What the TIDAL-style artist page shows: albums split into full albums and EPs & singles,
/// mixes, and similar artists.
@MainActor
@Observable
final class ArtistOverviewViewModel {
    private(set) var albums: [AlbumSummary] = []
    private(set) var epsAndSingles: [AlbumSummary] = []
    private(set) var mixes: [Mix] = []
    private(set) var similar: [ArtistSummary] = []
    private(set) var allTracks: [Track] = []
    private var loadedKey: String?

    /// Like TIDAL: up to 6 songs and under 30 minutes is an EP or a single.
    static func isEPOrSingle(_ album: AlbumSummary) -> Bool {
        album.trackCount <= 6 && album.duration < 30 * 60
    }

    /// "Single" for up to 3 songs, "EP" for more; "Album" otherwise.
    static func kind(_ album: AlbumSummary) -> String {
        guard isEPOrSingle(album) else { return "Album" }
        return album.trackCount <= 3 ? "Single" : "EP"
    }

    func load(artist: ArtistSummary, from database: LibraryDatabase) async {
        if loadedKey != artist.artistKey {
            albums = []; epsAndSingles = []; mixes = []; similar = []; allTracks = []
        }
        let all = (try? await database.albums(sortedBy: .year, artistKey: artist.artistKey)) ?? []
        let mixes = (try? await database.artistMixes(for: artist)) ?? []
        let similar = (try? await database.similarArtists(to: artist.artistKey)) ?? []
        var tracks: [Track] = []
        for album in all { tracks += (try? await database.tracks(inAlbum: album.albumKey)) ?? [] }
        guard !Task.isCancelled else { return }
        albums = all.filter { !Self.isEPOrSingle($0) }
        epsAndSingles = all.filter(Self.isEPOrSingle)
        self.mixes = mixes
        self.similar = similar
        allTracks = tracks
        loadedKey = artist.artistKey
    }
}
