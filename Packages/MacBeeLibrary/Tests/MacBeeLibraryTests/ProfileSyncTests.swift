import XCTest
@testable import MacBeeLibrary

final class ProfileSyncTests: XCTestCase {
    /// A library on "drive" with the same three songs.
    func library(drive: String) async throws -> (LibraryDatabase, [Int64]) {
        let db = try LibraryDatabase()
        let folder = try await db.insertFolder(path: "/Volumes/\(drive)", name: drive)
        let batch = (1...3).map { n -> ScannedTrack in
            var t = ScannedTrack(path: "/Volumes/\(drive)/Ride/Nowhere/0\(n).flac", fileSize: 1, modifiedAt: Date())
            t.title = "Song \(n)"; t.artist = "Ride"; t.album = "Nowhere"; t.duration = 200; t.codec = "FLAC"
            return t
        }
        _ = try await db.save(batch, folderId: folder.id!)
        let ids = try await db.search("Song").sorted { $0.path < $1.path }.compactMap(\.id)
        return (db, ids)
    }

    func testPlaysFavoritesAndPlaylistsMoveAcross() async throws {
        let (macA, a) = try await library(drive: "2 Set Music")
        let (macB, b) = try await library(drive: "Music Copy") // different drive name: matched by path below it
        let when = Date(timeIntervalSince1970: 1_760_000_000)
        try await macA.recordPlay(trackId: a[0], at: when)
        try await macA.setFavorite(trackId: a[1], true)
        let playlist = try await macA.createPlaylist(name: "Shoegaze")
        try await macA.addTracks([a[2], a[0]], toPlaylist: playlist.id!)

        let report = try await macB.mergeProfile(try await macA.profileSnapshot(deviceName: "A"))
        XCTAssertEqual(report.playsAdded, 1)
        XCTAssertEqual(report.favoritesAdded, 1)
        XCTAssertEqual(report.playlistsAdded, 1)
        XCTAssertEqual(report.playlistSongsAdded, 2)
        let song0 = try await macB.track(id: b[0])
        let song1 = try await macB.track(id: b[1])
        XCTAssertEqual(song0?.playCount, 1)
        XCTAssertEqual(song1?.isFavorite, true)

        // Syncing again adds nothing twice.
        let again = try await macB.mergeProfile(try await macA.profileSnapshot(deviceName: "A"))
        XCTAssertEqual(again, ProfileMergeReport())
    }

    func testMirrorReplacesPlaylistsAndFavorites() async throws {
        let (macA, a) = try await library(drive: "A")
        let (macB, b) = try await library(drive: "B")
        let mine = try await macA.createPlaylist(name: "Keep Me")
        try await macA.addTracks([a[0]], toPlaylist: mine.id!)
        _ = try await macB.createPlaylist(name: "Test Playlist on B")
        try await macB.setFavorite(trackId: b[2], true)

        _ = try await macB.mirrorProfile(try await macA.profileSnapshot(deviceName: "A"))
        let names = try await macB.playlists().map(\.name)
        XCTAssertEqual(names, ["Keep Me"])
        let unfavored = try await macB.track(id: b[2])
        XCTAssertEqual(unfavored?.isFavorite, false)
    }
}
