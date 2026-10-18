import XCTest
@testable import MacBeeLibrary

final class DuplicateFinderTests: XCTestCase {
    func song(_ id: Int64, title: String = "Losers", duration: Double = 207, priority: Int = 0, quality: Double = 705_600)
        -> DuplicateFinder.Song {
        .init(id: id, artist: "Balthazar", title: title, album: "Sand", duration: duration, folderPriority: priority, quality: quality)
    }

    func testHigherPriorityFolderWins() {
        let result = DuplicateFinder.duplicates(in: [song(1, priority: 1), song(2, priority: 0)])
        XCTAssertEqual(result, [1: 2])
    }

    func testBetterQualityWinsInTheSameFolderPriority() {
        let result = DuplicateFinder.duplicates(in: [song(1, quality: 705_600), song(2, quality: 2_304_000)])
        XCTAssertEqual(result, [1: 2])
    }

    func testDurationsMoreThanTwoSecondsApartAreDifferentSongs() {
        XCTAssertTrue(DuplicateFinder.duplicates(in: [song(1, duration: 200), song(2, duration: 203)]).isEmpty)
        XCTAssertEqual(DuplicateFinder.duplicates(in: [song(1, duration: 200), song(2, duration: 201.5)]).count, 1)
    }

    func testApostrophesAndPunctuationDontMatter() {
        var curly = song(2, title: "Sweet Child o’ Mine")
        curly.artist = "Guns N’ Roses"
        var straight = song(1, title: "Sweet Child O' Mine")
        straight.artist = "Guns N' Roses"
        XCTAssertEqual(DuplicateFinder.duplicates(in: [straight, curly]).count, 1)
    }

    func testCaseAndAccentsDontMatterButTitlesDo() {
        var other = song(2)
        other.artist = "BALTHAZAR"
        XCTAssertEqual(DuplicateFinder.duplicates(in: [song(1), other]).count, 1)
        XCTAssertTrue(DuplicateFinder.duplicates(in: [song(1), song(2, title: "Bunker")]).isEmpty)
        XCTAssertTrue(DuplicateFinder.duplicates(in: [song(1, title: ""), song(2, title: "")]).isEmpty)
    }
}

final class SourcesTests: XCTestCase {
    var db: LibraryDatabase!

    override func setUp() async throws {
        db = try LibraryDatabase()
    }

    /// One copy of "Sand" in a folder; returns the folder id and the song's id.
    func addCopy(folder path: String, bits: Int = 16) async throws -> (folder: Int64, track: Int64) {
        let folder = try await db.insertFolder(path: path, name: path)
        var t = ScannedTrack(path: "\(path)/Balthazar/Sand/02.flac", fileSize: 1000, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        t.title = "Losers"; t.artist = "Balthazar"; t.album = "Sand"; t.trackNumber = 2; t.duration = 207
        t.bitDepth = bits; t.sampleRate = 44_100; t.codec = "FLAC"
        _ = try await db.save([t], folderId: folder.id!)
        let id = try await db.search("Losers").first { $0.path.hasPrefix(path) }?.id
        return (folder.id!, id ?? -1)
    }

    func testDuplicatesShowOnceAndFollowFolderPriority() async throws {
        let first = try await addCopy(folder: "/A")
        let second = try await addCopy(folder: "/B", bits: 24)
        try await db.refreshVisibility()
        var shown = try await db.search("Losers")
        XCTAssertEqual(shown.map(\.id), [first.track], "the first folder's copy shows, even though the other is 24-bit")
        let stats = try await db.stats()
        XCTAssertEqual(stats.tracks, 1)

        try await db.setFolderOrder([second.folder, first.folder])
        try await db.refreshVisibility()
        shown = try await db.search("Losers")
        XCTAssertEqual(shown.map(\.id), [second.track])
        let alternatives = try await db.alternativeFiles(forTrackId: second.track)
        XCTAssertEqual(alternatives, ["/A/Balthazar/Sand/02.flac"])
    }

    func testPausedFolderSongsAreLeftOut() async throws {
        let first = try await addCopy(folder: "/A")
        let second = try await addCopy(folder: "/B")
        try await db.setFolderPaused(id: first.folder, true)
        try await db.refreshVisibility()
        let shown = try await db.search("Losers")
        XCTAssertEqual(shown.map(\.id), [second.track])
        let alternatives = try await db.alternativeFiles(forTrackId: second.track)
        XCTAssertTrue(alternatives.isEmpty, "paused folders give no failover copies")
        let folders = try await db.folders()
        XCTAssertEqual(folders.first { $0.id == first.folder }?.isPaused, true)
    }

    func testDuplicatesPageAndRemovingCopies() async throws {
        let first = try await addCopy(folder: "/A")
        let second = try await addCopy(folder: "/B")
        try await db.refreshVisibility()
        var groups = try await db.duplicateGroups()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].copies.map(\.track.id), [first.track, second.track])
        try await db.excludeTracks([second.track])
        try await db.refreshVisibility()
        groups = try await db.duplicateGroups()
        XCTAssertTrue(groups.isEmpty)
        let removed = try await db.excludedTrackCount()
        XCTAssertEqual(removed, 1)
        try await db.restoreExcludedTracks()
        try await db.refreshVisibility()
        groups = try await db.duplicateGroups()
        XCTAssertEqual(groups.count, 1)
    }

    func testNewFoldersGoToTheBottom() async throws {
        _ = try await db.insertFolder(path: "/Z", name: "Z")
        _ = try await db.insertFolder(path: "/A", name: "A")
        let folders = try await db.folders()
        XCTAssertEqual(folders.map(\.path), ["/Z", "/A"])
    }

    func testCompilationOnlyArtistsCanBeHidden() async throws {
        let folder = try await db.insertFolder(path: "/M", name: "M")
        var own = ScannedTrack(path: "/M/A/1.flac", fileSize: 1, modifiedAt: Date())
        own.title = "Own"; own.artist = "Solo"; own.album = "Solo Album"; own.duration = 100; own.codec = "FLAC"
        var guest = ScannedTrack(path: "/M/C/1.flac", fileSize: 1, modifiedAt: Date())
        guest.title = "Guest"; guest.artist = "Guest Star"; guest.albumArtist = "Guest Star"; guest.album = "Hits"
        guest.isCompilation = true; guest.duration = 100; guest.codec = "FLAC"
        // An untagged compilation: three artists in one folder.
        let untagged = ["Band One", "Band Two", "Band Three"].enumerated().map { index, artist -> ScannedTrack in
            var t = ScannedTrack(path: "/M/Tribute/\(index).flac", fileSize: 1, modifiedAt: Date())
            t.title = "Cover \(index)"; t.artist = artist; t.album = "Tribute"; t.duration = 100; t.codec = "FLAC"
            return t
        }
        _ = try await db.save([own, guest] + untagged, folderId: folder.id!)
        try await db.refreshVisibility()
        let all = try await db.artists().map(\.name)
        let hidden = try await db.artists(hidingCompilationOnly: true).map(\.name)
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(hidden, ["Solo"])
        // Compilations under Various Artists: the tagged "Hits" and the untagged "Tribute" (three artists, one album).
        let compilations = try await db.compilationAlbums()
        XCTAssertEqual(compilations.map(\.title), ["Hits", "Tribute"])
        XCTAssertEqual(compilations.map(\.artist), ["Various Artists", "Various Artists"])
        let tribute = try await db.tracks(inAlbum: compilations[1].albumKey)
        XCTAssertEqual(tribute.map(\.artist), ["Band One", "Band Two", "Band Three"])
    }
}
