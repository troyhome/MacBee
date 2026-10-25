import XCTest
@testable import MacBeeLibrary

final class RememberedSongsTests: XCTestCase {
    func addFolder(_ db: LibraryDatabase, root: String) async throws -> (Int64, [Int64]) {
        let folder = try await db.insertFolder(path: root, name: (root as NSString).lastPathComponent)
        let batch = (1...3).map { n -> ScannedTrack in
            var t = ScannedTrack(path: "\(root)/Ride/Nowhere/0\(n).flac", fileSize: 1, modifiedAt: Date())
            t.title = "Song \(n)"; t.artist = "Ride"; t.album = "Nowhere"; t.duration = 200; t.codec = "FLAC"
            return t
        }
        _ = try await db.save(batch, folderId: folder.id!)
        let ids = try await db.search("Song").sorted { $0.path < $1.path }.compactMap(\.id)
        return (folder.id!, ids)
    }

    func testFavoritesPlaysPlaylistsAndMixesComeBackWhenSongsReturn() async throws {
        let db = try LibraryDatabase()
        let (folderId, old) = try await addFolder(db, root: "/Volumes/2 Set Music")
        let when = Date(timeIntervalSince1970: 1_760_000_000)
        try await db.setFavorite(trackId: old[0], true)
        try await db.recordPlay(trackId: old[1], at: when)
        let playlist = try await db.createPlaylist(name: "Shoegaze")
        try await db.addTracks([old[2], old[0]], toPlaylist: playlist.id!)
        try await db.saveMix(title: "Ride Mix", subtitle: "", trackIds: [old[1], old[2]])

        let remembered = try await db.rememberSongs(inFolder: folderId)
        try await db.deleteFolder(id: folderId)
        let emptied = try await db.playlistEntries(playlistId: playlist.id!)
        XCTAssertTrue(emptied.isEmpty)

        // Nothing to match yet: everything waits.
        let early = try await db.restoreRemembered(remembered)
        XCTAssertEqual(early.restored, 0)
        XCTAssertEqual(early.left, remembered)

        // Same songs added back from a different place.
        let (_, new) = try await addFolder(db, root: "/Users/troy/MountPoints/music")
        let result = try await db.restoreRemembered(early.left)
        XCTAssertTrue(result.left.isEmpty)
        let song0 = try await db.track(id: new[0])
        let song1 = try await db.track(id: new[1])
        XCTAssertEqual(song0?.isFavorite, true)
        XCTAssertEqual(song1?.playCount, 1)
        let entries = try await db.playlistEntries(playlistId: playlist.id!)
        XCTAssertEqual(entries.map(\.track.id), [new[2], new[0]])
        let mixes = try await db.savedMixes()
        XCTAssertEqual(mixes.first?.tracks.map(\.id), [new[1], new[2]])

        // Restoring again adds nothing twice.
        let again = try await db.restoreRemembered(remembered)
        XCTAssertEqual(again.restored, 0)
    }

    func testSavesToFileAndEmptyRemovesIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("remembered-\(UUID().uuidString).json")
        var remembered = RememberedSongs()
        remembered.songs = [.init(key: .init(relativePath: "a/b.flac", fingerprint: "x"), isFavorite: true, rating: nil)]
        try remembered.save(to: url)
        XCTAssertEqual(RememberedSongs.load(from: url), remembered)
        try RememberedSongs().save(to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
