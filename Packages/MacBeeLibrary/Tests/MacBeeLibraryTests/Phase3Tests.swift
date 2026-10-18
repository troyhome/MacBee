import XCTest
@testable import MacBeeLibrary

final class Phase3Tests: XCTestCase {
    func track(_ n: Int, duration: Double) -> Track {
        Track(id: Int64(n), folderId: 1, path: "/m/\(n).flac", fileSize: 1, modifiedAt: Date(), title: "\(n)", artist: nil,
              albumArtist: nil, album: nil, genre: nil, composer: nil, year: nil, trackNumber: nil, trackTotal: nil,
              discNumber: nil, discTotal: nil, isCompilation: false, duration: duration, sampleRate: nil, bitDepth: nil,
              channels: nil, bitrate: nil, codec: "FLAC", displayAlbum: "", displayAlbumArtist: "", albumKey: "",
              artistKey: "", artworkId: nil, dateAdded: Date(), playCount: 0, lastPlayedAt: nil, isFavorite: false,
              rating: nil, isMissing: false)
    }

    func testFillStaysWithinCapacity() {
        let songs = (1...40).map { track($0, duration: Double(150 + $0 * 7)) }
        let picked = CapacityFiller.fill(existing: [], candidates: songs, capacity: 74 * 60)
        let total = picked.reduce(0) { $0 + $1.duration }
        XCTAssertLessThanOrEqual(total, 74 * 60)
        XCTAssertGreaterThan(total, 69 * 60)
    }

    func testFillSkipsSongsAlreadyThere() {
        let songs = [track(1, duration: 200), track(2, duration: 200)]
        XCTAssertEqual(CapacityFiller.fill(existing: [songs[0]], candidates: songs, capacity: 1000).map(\.id), [2])
    }

    func testStatus() {
        XCTAssertEqual(CapacityFiller.status(total: 4500, capacity: 4440), .overtime(60))
        XCTAssertEqual(CapacityFiller.status(total: 3600, capacity: 4440), .underfill(840))
        XCTAssertEqual(CapacityFiller.status(total: 4200, capacity: 4440), .fits)
    }

    func testRelativeAndAbsolutePaths() {
        let dir = URL(fileURLWithPath: "/Volumes/Music/Playlists")
        XCTAssertEqual(M3UPlaylist.relativePath("/Volumes/Music/Ride/Nowhere/01.flac", to: dir), "../Ride/Nowhere/01.flac")
        XCTAssertEqual(M3UPlaylist.relativePath("/Volumes/Music/Playlists/x.flac", to: dir), "x.flac")
        XCTAssertEqual(M3UPlaylist.relativePath("/Volumes/Other/a.flac", to: dir), "/Volumes/Other/a.flac")
        let t = track(1, duration: 100)
        XCTAssertTrue(M3UPlaylist.export([t], relativeTo: dir, style: .absolute).contains("\n/m/1.flac\n"))
    }

    func testSavedMixesAndSmartPlaylists() async throws {
        let db = try LibraryDatabase()
        let folder = try await db.insertFolder(path: "/M", name: "M")
        let batch = (1...3).map { n -> ScannedTrack in
            var t = ScannedTrack(path: "/M/\(n).flac", fileSize: 1, modifiedAt: Date())
            t.title = "Song \(n)"; t.artist = "A"; t.album = "B"; t.duration = 100; t.codec = "FLAC"
            return t
        }
        _ = try await db.save(batch, folderId: folder.id!)
        let ids = try await db.search("Song").compactMap(\.id)
        try await db.saveMix(title: "Rock Mix", subtitle: "From your Rock albums", trackIds: ids)
        let saved = try await db.savedMixes()
        XCTAssertEqual(saved.map(\.title), ["Rock Mix"])
        XCTAssertEqual(saved[0].tracks.count, 3)
        try await db.recordPlay(trackId: ids[1])
        try await db.setFavorite(trackId: ids[2], true)
        let mostPlayed = try await db.tracks(for: .mostPlayed)
        let topRated = try await db.tracks(for: .topRated)
        let recent = try await db.tracks(for: .recentlyAdded)
        XCTAssertEqual(mostPlayed.map(\.id), [ids[1]])
        XCTAssertEqual(topRated.map(\.id), [ids[2]])
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(SmartPlaylist(playlistId: -2), .mostPlayed)
        try await db.deleteSavedMix(id: saved[0].id)
        let none = try await db.savedMixes()
        XCTAssertTrue(none.isEmpty)
    }

    func testImportMatchesPathsFromAnotherComputer() async throws {
        let db = try LibraryDatabase()
        let folder = try await db.insertFolder(path: "/Volumes/2 Set Music", name: "2 Set Music")
        var t = ScannedTrack(path: "/Volumes/2 Set Music/Ride/Nowhere/01 Seagull.flac", fileSize: 1, modifiedAt: Date())
        t.title = "Seagull"; t.artist = "Ride"; t.album = "Nowhere"; t.duration = 100; t.codec = "FLAC"
        _ = try await db.save([t], folderId: folder.id!)
        let found = try await db.tracks(atPaths: ["/Users/someone/Music/Ride/Nowhere/01 Seagull.flac"])
        XCTAssertEqual(found.map(\.title), ["Seagull"])
    }
}
