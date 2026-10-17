import XCTest
@testable import MacBeeLibrary

final class CollectionQueriesTests: XCTestCase {
    var db: LibraryDatabase!
    var folderId: Int64!

    override func setUp() async throws {
        db = try LibraryDatabase()
        folderId = try await db.insertFolder(path: "/M", name: "M").id
    }

    private func addAlbum(_ album: String, count: Int) async throws -> [Int64] {
        let batch = (1...count).map { n -> ScannedTrack in
            var t = ScannedTrack(path: "/M/A/\(album)/\(n).flac", fileSize: Int64(1000 + n),
                                 modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
            t.title = "\(album) \(n)"; t.artist = "A"; t.album = album; t.trackNumber = n; t.duration = 200
            t.codec = "FLAC"
            return t
        }
        _ = try await db.save(batch, folderId: folderId)
        return try await db.search(album, limit: 100).filter { $0.displayAlbum == album }.compactMap(\.id)
    }

    func testFavoriteTracksListsOnlyFavorites() async throws {
        let ids = try await addAlbum("One", count: 3)
        try await db.setFavorite(trackId: ids[1], true)
        let favorites = try await db.favoriteTracks()
        XCTAssertEqual(favorites.map(\.id), [ids[1]])
    }

    func testAlbumIsFavoriteOnlyWhenEverySongIs() async throws {
        let whole = try await addAlbum("Whole", count: 2)
        let part = try await addAlbum("Part", count: 2)
        for id in whole { try await db.setFavorite(trackId: id, true) }
        try await db.setFavorite(trackId: part[0], true)
        let albums = try await db.favoriteAlbums()
        XCTAssertEqual(albums.map(\.title), ["Whole"])
    }
}
