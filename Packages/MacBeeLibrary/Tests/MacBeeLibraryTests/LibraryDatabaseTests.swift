import XCTest
@testable import MacBeeLibrary

final class LibraryDatabaseTests: XCTestCase {
    var db: LibraryDatabase!
    var folderId: Int64!

    override func setUp() async throws {
        db = try LibraryDatabase()
        folderId = try await db.insertFolder(path: "/Volumes/Music", name: "Music").id
    }

    func scanned(_ path: String, title: String, artist: String, album: String?,
                 track: Int, size: Int64 = 1000, duration: Double = 200) -> ScannedTrack {
        var t = ScannedTrack(path: path, fileSize: size, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        t.title = title
        t.artist = artist
        t.album = album
        t.trackNumber = track
        t.duration = duration
        t.sampleRate = 96_000
        t.bitDepth = 24
        t.codec = "FLAC"
        return t
    }

    func testSaveAndGroupIntoAlbums() async throws {
        let counts = try await db.save([
            scanned("/Volumes/Music/Bjork/Volta/04.flac", title: "Innocence", artist: "Björk", album: "Volta", track: 4),
            scanned("/Volumes/Music/Bjork/Volta/05.flac", title: "I See Who You Are", artist: "Björk", album: "Volta", track: 5, size: 2000),
            scanned("/Volumes/Music/Beady Eye/BE/07.flac", title: "I'm Just Saying", artist: "Beady Eye", album: "BE", track: 7, size: 3000),
        ], folderId: folderId)
        XCTAssertEqual(counts.added, 3)

        let stats = try await db.stats()
        XCTAssertEqual(stats, LibraryStats(artists: 2, albums: 2, tracks: 3, totalDuration: 600))

        let albums = try await db.albums(sortedBy: .artist)
        XCTAssertEqual(albums.map(\.title), ["BE", "Volta"])
        XCTAssertEqual(albums.last?.trackCount, 2)
        XCTAssertEqual(albums.last?.maxBitDepth, 24)

        let volta = try await db.tracks(inAlbum: albums[1].albumKey)
        XCTAssertEqual(volta.map(\.trackNumber), [4, 5])
        let byKey = try await db.album(key: albums[1].albumKey)
        XCTAssertEqual(byKey?.title, "Volta")
        XCTAssertEqual(byKey?.trackCount, 2)
    }

    func testRescanUpdatesWithoutDuplicates() async throws {
        let track = scanned("/Volumes/Music/a.flac", title: "Old", artist: "A", album: "X", track: 1)
        _ = try await db.save([track], folderId: folderId)
        var retagged = track
        retagged.title = "New"
        let counts = try await db.save([retagged], folderId: folderId)
        XCTAssertEqual(counts.updated, 1)
        let results = try await db.search("New")
        XCTAssertEqual(results.count, 1)
        let stats = try await db.stats()
        XCTAssertEqual(stats.tracks, 1)
    }

    func testMovedFileKeepsHistory() async throws {
        _ = try await db.save([scanned("/Volumes/Music/old/a.flac", title: "Song", artist: "A", album: "X", track: 1)],
                              folderId: folderId)
        let original = try await db.search("Song").first!
        try await db.recordPlay(trackId: original.id!)
        try await db.setMissing([original.id!], true)

        // Same file shows up somewhere else.
        let counts = try await db.save([scanned("/Volumes/Music/new/a.flac", title: "Song", artist: "A", album: "X", track: 1)],
                                       folderId: folderId)
        XCTAssertEqual(counts.moved, 1)
        let moved = try await db.track(id: original.id!)
        XCTAssertEqual(moved?.path, "/Volumes/Music/new/a.flac")
        XCTAssertEqual(moved?.playCount, 1)
        XCTAssertEqual(moved?.isMissing, false)
    }

    func testMissingTracksAreHidden() async throws {
        _ = try await db.save([scanned("/Volumes/Music/a.flac", title: "Gone", artist: "A", album: "X", track: 1)],
                              folderId: folderId)
        let id = try await db.search("Gone").first!.id!
        try await db.setMissing([id], true)
        let stats = try await db.stats()
        let results = try await db.search("Gone")
        XCTAssertEqual(stats.tracks, 0)
        XCTAssertTrue(results.isEmpty)
    }

    func testCleaningUpMissingTracks() async throws {
        _ = try await db.save([scanned("/Volumes/Music/a.flac", title: "Gone", artist: "A", album: "X", track: 1),
                               scanned("/Volumes/Music/b.flac", title: "Here", artist: "A", album: "X", track: 2, size: 2000)],
                              folderId: folderId)
        let gone = try await db.search("Gone").first!.id!
        try await db.recordPlay(trackId: gone)
        try await db.setMissing([gone], true)

        let missing = try await db.missingTracks()
        XCTAssertEqual(missing.map(\.displayTitle), ["Gone"])
        let removed = try await db.removeMissingTracks()
        XCTAssertEqual(removed, 1)
        let count = try await db.missingTrackCount()
        XCTAssertEqual(count, 0)
        let history = try await db.playHistory()
        XCTAssertTrue(history.isEmpty)
        let stats = try await db.stats()
        XCTAssertEqual(stats.tracks, 1)
    }

    func testRemovingFolderRemovesItsTracks() async throws {
        _ = try await db.save([scanned("/Volumes/Music/a.flac", title: "T", artist: "A", album: "X", track: 1)],
                              folderId: folderId)
        try await db.deleteFolder(id: folderId)
        let stats = try await db.stats()
        XCTAssertEqual(stats, .empty)
    }
}
