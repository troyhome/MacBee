import Foundation
import MacBeeLibrary
import Observation

/// Search results: artists and albums by name (accent-insensitive), songs from the database search.
@MainActor
@Observable
final class SearchViewModel {
    private(set) var artists: [ArtistSummary] = []
    private(set) var albums: [AlbumSummary] = []
    private(set) var tracks: [Track] = []
    private(set) var searchedText = ""

    /// Full artist/album lists, kept until the library changes.
    @ObservationIgnored private var allArtists: [ArtistSummary] = []
    @ObservationIgnored private var allAlbums: [AlbumSummary] = []
    @ObservationIgnored private var loadedRevision: Int?

    var isEmpty: Bool { artists.isEmpty && albums.isEmpty && tracks.isEmpty }

    func search(_ text: String, in database: LibraryDatabase, revision: Int) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            artists = []; albums = []; tracks = []; searchedText = ""
            return
        }
        if loadedRevision != revision {
            allArtists = (try? await database.artists()) ?? []
            allAlbums = (try? await database.albums(sortedBy: .artist)) ?? []
            loadedRevision = revision
        }
        let foundTracks = (try? await database.search(query, limit: 300)) ?? []
        guard !Task.isCancelled else { return }
        artists = Array(allArtists.filter { Self.matches($0.name, query) }.prefix(12))
        albums = Array(allAlbums.filter { Self.matches($0.title, query) || Self.matches($0.artist, query) }.prefix(30))
        tracks = foundTracks
        searchedText = query
    }

    /// Ignores case and accents, so "bjork" finds "Björk".
    private static func matches(_ value: String, _ query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
