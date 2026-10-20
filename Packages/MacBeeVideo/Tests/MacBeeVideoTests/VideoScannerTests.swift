import XCTest
@testable import MacBeeVideo

final class VideoScannerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacBeeVideoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Makes a sparse file of the given size (takes no real disk space).
    func make(_ path: String, size: Int64 = 30_000_000) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }

    func testMoviesShowsPostersAndGenres() throws {
        try make("Drive (2011) [imdbid-tt0780504]/Drive (2011) V2 (2160p BluRay x265 10bit HDR Tigole).mkv")
        try make("Big Fish (2003) {tmdb-587}/Big Fish (2003).mkv", size: 40_000_000)
        try make("Big Fish (2003) {tmdb-587}/Big Fish (2003).mp4")
        try make("Big Fish (2003) {tmdb-587}/Big Fish (2003).jpg", size: 10)
        try make("Office Space (1999).mkv")
        try make("Office Space (1999)-trailer.mkv", size: 1_000) // too small: an extra
        try make("Scrubs (2026)/Season 1/Scrubs.(2026).-.S01E02.-.My.2nd.First.Day.mkv")
        try make("Scrubs (2026)/Season 1/Scrubs.(2026).-.S01E01.-.My.Return.mkv")
        try make("Scrubs (2026)/Season 02/Scrubs (2026) - 2x01 - My First Time in a While.mkv")
        try make("Scrubs (2026)/folder.jpg", size: 10)
        try make("Friends.Complete.Series.720p/Friends.Sample.mkv")
        try "<movie><genre>Crime</genre><genre>Drama</genre></movie>"
            .write(to: root.appendingPathComponent("Drive (2011) [imdbid-tt0780504]/movie.nfo"), atomically: true, encoding: .utf8)

        let catalog = VideoScanner.scan([.init(url: root, kind: .moviesAndShows)])

        XCTAssertEqual(catalog.movies.map(\.title), ["Big Fish", "Drive", "Office Space"])
        let bigFish = catalog.movies[0]
        XCTAssertEqual(bigFish.files.count, 2)
        XCTAssertTrue(bigFish.files[0].path.hasSuffix(".mkv"), "the larger copy comes first")
        XCTAssertTrue(bigFish.posterPath?.hasSuffix("Big Fish (2003).jpg") == true)
        let drive = catalog.movies[1]
        XCTAssertTrue(drive.is4K && drive.isHDR)
        XCTAssertEqual(drive.genres, ["Crime", "Drama"])

        XCTAssertEqual(catalog.shows.count, 1)
        let scrubs = catalog.shows[0]
        XCTAssertEqual(scrubs.title, "Scrubs")
        XCTAssertEqual(scrubs.year, 2026)
        XCTAssertEqual(scrubs.seasons.map(\.number), [1, 2])
        XCTAssertEqual(scrubs.seasons[0].episodes.map(\.number), [1, 2])
        XCTAssertEqual(scrubs.seasons[0].episodes[0].title, "My Return")
        XCTAssertTrue(scrubs.posterPath?.hasSuffix("folder.jpg") == true)
        XCTAssertEqual(catalog.genres, ["Crime", "Drama"])
    }

    func testMusicVideoFolders() throws {
        try make("Balthazar/Losers (Official Video).mp4")
        let catalog = VideoScanner.scan([.init(url: root, kind: .musicVideos)])
        XCTAssertEqual(catalog.musicVideos.map(\.title), ["Losers (Official Video)"])
        XCTAssertEqual(catalog.musicVideos.first?.folderName, "Balthazar")
        XCTAssertTrue(catalog.movies.isEmpty)
    }

    func testMusicVideosOnTwoDrivesShowOnce() throws {
        try make("A/Balthazar/Losers.mp4")
        try make("B/Balthazar/Losers.mp4")
        let catalog = VideoScanner.scan([.init(url: root.appendingPathComponent("A"), kind: .musicVideos),
                                         .init(url: root.appendingPathComponent("B"), kind: .musicVideos)])
        XCTAssertEqual(catalog.musicVideos.count, 1)
        XCTAssertTrue(catalog.musicVideos[0].file.path.contains("/A/"))
        XCTAssertEqual(catalog.musicVideos[0].otherFiles?.count, 1, "the other drive's copy is kept for the Duplicates page")
    }

    func testStoreRoundTrip() throws {
        try make("Office Space (1999).mkv")
        let catalog = VideoScanner.scan([.init(url: root, kind: .moviesAndShows)])
        let file = root.appendingPathComponent("cache/videos.json")
        VideoCatalogStore.save(catalog, to: file)
        XCTAssertEqual(VideoCatalogStore.load(from: file), catalog)
    }

    /// Two video folders with the same films and episodes: each shows once, from the first folder.
    func testSameVideosInTwoFoldersShowOnce() throws {
        try make("A/Heat (1995)/Heat (1995).mkv", size: 30_000_000)
        try make("B/Heat (1995)/Heat (1995).mkv", size: 40_000_000)   // bigger, but the second folder
        try make("B/Heat.mkv", size: 35_000_000)                       // no year: still the same film
        try make("A/Scrubs/Season 1/Scrubs S01E01.mkv")
        try make("B/Scrubs/Season 1/Scrubs S01E01.mkv")
        try make("B/Scrubs/Season 1/Scrubs S01E02.mkv")               // only in the second folder: fills in
        let catalog = VideoScanner.scan([.init(url: root.appendingPathComponent("A"), kind: .moviesAndShows),
                                         .init(url: root.appendingPathComponent("B"), kind: .moviesAndShows)])
        XCTAssertEqual(catalog.movies.count, 1)
        XCTAssertEqual(catalog.movies[0].files.count, 3)
        XCTAssertTrue(catalog.movies[0].files[0].path.contains("/A/"), "the first folder's copy is shown")
        XCTAssertEqual(catalog.shows.count, 1)
        let episodes = catalog.shows[0].seasons[0].episodes
        XCTAssertEqual(episodes.map(\.number), [1, 2])
        XCTAssertTrue(episodes[0].file.path.contains("/A/"))
        XCTAssertEqual(episodes[0].otherFiles?.count, 1)
        XCTAssertTrue(episodes[1].file.path.contains("/B/"))
    }
}
