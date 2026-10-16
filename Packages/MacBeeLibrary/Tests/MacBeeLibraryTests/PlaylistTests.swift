import XCTest
@testable import MacBeeLibrary

final class PlaylistTests: XCTestCase {
    var db: LibraryDatabase!
    var folderId: Int64!

    override func setUp() async throws {
        db = try LibraryDatabase()
        folderId = try await db.insertFolder(path: "/M", name: "M").id
    }

    /// Adds songs and returns their ids in order.
    func addSongs(_ titles: [String], album: String = "A", genre: String? = nil, year: Int? = nil,
                  codec: String = "FLAC", bits: Int = 16, rate: Double = 44_100, rating: Int? = nil) async throws -> [Int64] {
        let batch = titles.enumerated().map { i, title -> ScannedTrack in
            var t = ScannedTrack(path: "/M/\(album)/\(title).flac", fileSize: Int64(1000 + i),
                                 modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
            t.title = title; t.artist = "Artist"; t.album = album; t.trackNumber = i + 1
            t.genre = genre; t.year = year; t.codec = codec; t.bitDepth = bits; t.sampleRate = rate
            t.duration = 100; t.rating = rating
            return t
        }
        _ = try await db.save(batch, folderId: folderId)
        var ids: [Int64] = []
        for title in titles { ids.append(try await db.search(title).first { $0.displayTitle == title }!.id!) }
        return ids
    }

    // MARK: Folders and order

    func testFoldersNestAndMove() async throws {
        let folder = try await db.createPlaylist(name: "Mixes", isFolder: true)
        let a = try await db.createPlaylist(name: "A")
        let b = try await db.createPlaylist(name: "B", parentFolderId: folder.id)
        var tree = PlaylistTree.build(try await db.playlists())
        XCTAssertEqual(tree.map(\.playlist.name), ["Mixes", "A"])
        XCTAssertEqual(tree[0].children.map(\.playlist.name), ["B"])

        try await db.movePlaylist(id: a.id!, toFolder: folder.id, at: 0)
        tree = PlaylistTree.build(try await db.playlists())
        XCTAssertEqual(tree.map(\.playlist.name), ["Mixes"])
        XCTAssertEqual(tree[0].children.map(\.playlist.name), ["A", "B"])

        try await db.movePlaylist(id: b.id!, toFolder: nil, at: 0)
        tree = PlaylistTree.build(try await db.playlists())
        XCTAssertEqual(tree.map(\.playlist.name), ["B", "Mixes"])
    }

    func testFolderCannotMoveIntoItself() async throws {
        let outer = try await db.createPlaylist(name: "Outer", isFolder: true)
        let inner = try await db.createPlaylist(name: "Inner", isFolder: true, parentFolderId: outer.id)
        try await db.movePlaylist(id: outer.id!, toFolder: inner.id, at: 0)
        let tree = PlaylistTree.build(try await db.playlists())
        XCTAssertEqual(tree.map(\.playlist.name), ["Outer"])
        XCTAssertEqual(tree[0].children.map(\.playlist.name), ["Inner"])
    }

    func testDeletingFolderDeletesContentsButNotSongs() async throws {
        let ids = try await addSongs(["One"])
        let folder = try await db.createPlaylist(name: "F", isFolder: true)
        let p = try await db.createPlaylist(name: "P", parentFolderId: folder.id)
        try await db.addTracks(ids, toPlaylist: p.id!)
        try await db.deletePlaylist(id: folder.id!)
        let remaining = try await db.playlists()
        XCTAssertTrue(remaining.isEmpty)
        let stats = try await db.stats()
        XCTAssertEqual(stats.tracks, 1)
    }

    func testPlaylistPicture() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = try await MusicLibrary(location: LibraryLocation(directory: dir))
        let playlist = try await library.database.createPlaylist(name: "P")
        // A tiny valid PNG (1 x 1 pixel).
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/eL9LhQAAAABJRU5ErkJggg==")!
        try await library.setPlaylistArtwork(playlistId: playlist.id!, imageData: png)
        var saved = try await library.database.playlists().first!
        XCTAssertNotNil(saved.artworkId)
        let url = await library.artworkURL(for: saved.artworkId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))

        do {
            try await library.setPlaylistArtwork(playlistId: playlist.id!, imageData: Data("not an image".utf8))
            XCTFail("expected an error")
        } catch {}

        try await library.setPlaylistArtwork(playlistId: playlist.id!, imageData: nil)
        saved = try await library.database.playlists().first!
        XCTAssertNil(saved.artworkId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Songs in a playlist

    func testAddInsertRemoveReorder() async throws {
        let ids = try await addSongs(["One", "Two", "Three"])
        let p = try await db.createPlaylist(name: "P")
        try await db.addTracks([ids[0], ids[2]], toPlaylist: p.id!)
        try await db.addTracks([ids[1]], toPlaylist: p.id!, at: 1)
        var entries = try await db.playlistEntries(playlistId: p.id!)
        XCTAssertEqual(entries.map(\.track.displayTitle), ["One", "Two", "Three"])

        try await db.reorderEntries(playlistId: p.id!, itemIds: entries.reversed().map(\.itemId))
        entries = try await db.playlistEntries(playlistId: p.id!)
        XCTAssertEqual(entries.map(\.track.displayTitle), ["Three", "Two", "One"])

        try await db.removeEntries([entries[1].itemId], fromPlaylist: p.id!)
        entries = try await db.playlistEntries(playlistId: p.id!)
        XCTAssertEqual(entries.map(\.track.displayTitle), ["Three", "One"])

        let summary = try await db.playlistSummary(playlistId: p.id!)
        XCTAssertEqual(summary.trackCount, 2)
        XCTAssertEqual(summary.duration, 200)
    }

    func testSameSongTwiceAndMissingSongsHidden() async throws {
        let ids = try await addSongs(["One", "Two"])
        let p = try await db.createPlaylist(name: "P")
        try await db.addTracks([ids[0], ids[0], ids[1]], toPlaylist: p.id!)
        try await db.setMissing([ids[1]], true)
        var entries = try await db.playlistEntries(playlistId: p.id!)
        XCTAssertEqual(entries.map(\.track.displayTitle), ["One", "One"])

        try await db.setMissing([ids[1]], false) // file came back
        entries = try await db.playlistEntries(playlistId: p.id!)
        XCTAssertEqual(entries.count, 3)

        try await db.setMissing([ids[1]], true)
        _ = try await db.removeMissingTracks()   // cleaned up for good
        try await db.setMissing([ids[0]], false)
        entries = try await db.playlistEntries(playlistId: p.id!)
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: Playlist Studio

    func testFilters() async throws {
        _ = try await addSongs(["Jazz60s"], album: "J", genre: "Jazz", year: 1965, rating: 5)
        _ = try await addSongs(["Rock90s"], album: "R", genre: "rock", year: 1994, codec: "MP3", rating: 60)
        let hires = try await addSongs(["HiRes"], album: "H", genre: "Rock", year: 2015, bits: 24, rate: 96_000)
        try await db.recordPlay(trackId: hires[0])

        func titles(_ configure: (inout TrackFilter) -> Void) async throws -> [String] {
            var f = TrackFilter()
            configure(&f)
            return try await db.tracks(matching: f).map(\.displayTitle)
        }
        let rock = try await titles { $0.genre = "Rock" }
        XCTAssertEqual(Set(rock), ["Rock90s", "HiRes"])
        let nineties = try await titles { $0.yearFrom = 1990; $0.yearTo = 1999 }
        XCTAssertEqual(nineties, ["Rock90s"])
        let hiResOnly = try await titles { $0.format = .hiRes }
        XCTAssertEqual(hiResOnly, ["HiRes"])
        let lossless = try await titles { $0.format = .lossless }
        XCTAssertEqual(Set(lossless), ["Jazz60s", "HiRes"])
        let threeStars = try await titles { $0.minimumStars = 3 } // 5 stars, and 60/100 = 3 stars
        XCTAssertEqual(Set(threeStars), ["Jazz60s", "Rock90s"])
        let played = try await titles { $0.playCount = .atLeastOnce }
        XCTAssertEqual(played, ["HiRes"])
        let search = try await titles { $0.text = "jazz" }
        XCTAssertEqual(search, ["Jazz60s"])

        let genres = try await db.genres()
        XCTAssertEqual(Set(genres.map { $0.lowercased() }), ["jazz", "rock"])
    }

    func testSearchFieldsAndPlaylistSource() async throws {
        _ = try await addSongs(["Stupid Girl", "Queer"], album: "Garbage")       // artist "Artist", album "Garbage"
        let other = try await addSongs(["Garbage Day"], album: "Other")          // title contains "garbage"

        func titles(_ configure: (inout TrackFilter) -> Void) async throws -> Set<String> {
            var f = TrackFilter()
            f.text = "garbage"
            configure(&f)
            return Set(try await db.tracks(matching: f).map(\.displayTitle))
        }
        let everything = try await titles { _ in }
        XCTAssertEqual(everything, ["Stupid Girl", "Queer", "Garbage Day"])
        let albumOnly = try await titles { $0.searchFields = [.album] }
        XCTAssertEqual(albumOnly, ["Stupid Girl", "Queer"])
        let titleOnly = try await titles { $0.searchFields = [.title] }
        XCTAssertEqual(titleOnly, ["Garbage Day"])
        let artistOnly = try await titles { $0.searchFields = [.artist] }
        XCTAssertTrue(artistOnly.isEmpty)

        // Songs from one playlist, in playlist order, with filters still applied.
        let ids = try await addSongs(["One", "Two"], album: "Mix")
        let p = try await db.createPlaylist(name: "P")
        try await db.addTracks([ids[1], other[0], ids[0]], toPlaylist: p.id!)
        var f = TrackFilter()
        f.playlistId = p.id
        let inPlaylist = try await db.tracks(matching: f).map(\.displayTitle)
        XCTAssertEqual(inPlaylist, ["Two", "Garbage Day", "One"])
        f.text = "o"
        f.searchFields = [.title]
        let filtered = try await db.tracks(matching: f).map(\.displayTitle)
        XCTAssertEqual(filtered, ["Two", "One"])
    }

    // MARK: M3U

    func testM3UParseAndExport() async throws {
        let text = """
            \u{FEFF}#EXTM3U
            #EXTINF:200,Artist - One
            A/One.flac
            /M/A/Two.flac
            ..\\M\\A\\Three.flac
            http://example.com/stream.mp3

            """
        let paths = M3UPlaylist.parse(text, baseDirectory: URL(fileURLWithPath: "/M"))
        XCTAssertEqual(paths, ["/M/A/One.flac", "/M/A/Two.flac", "/M/A/Three.flac"])

        let ids = try await addSongs(["One", "Two"])
        let tracks = try await db.tracks(atPaths: ["/M/A/Two.flac", "/nope.flac", "/M/A/One.flac"])
        XCTAssertEqual(tracks.map(\.id), [ids[1], ids[0]])

        let exported = M3UPlaylist.export(tracks, relativeTo: URL(fileURLWithPath: "/M"))
        XCTAssertTrue(exported.hasPrefix("#EXTM3U\n#EXTINF:100,Artist - Two\nA/Two.flac\n"))
        let elsewhere = M3UPlaylist.export(tracks, relativeTo: URL(fileURLWithPath: "/Users/me/Desktop"))
        XCTAssertTrue(elsewhere.contains("\n/M/A/One.flac\n"))
        XCTAssertEqual(M3UPlaylist.parse(exported, baseDirectory: URL(fileURLWithPath: "/M")),
                       ["/M/A/Two.flac", "/M/A/One.flac"])
    }
}
