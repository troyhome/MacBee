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

    func testStoreRoundTrip() throws {
        try make("Office Space (1999).mkv")
        let catalog = VideoScanner.scan([.init(url: root, kind: .moviesAndShows)])
        let file = root.appendingPathComponent("cache/videos.json")
        VideoCatalogStore.save(catalog, to: file)
        XCTAssertEqual(VideoCatalogStore.load(from: file), catalog)
    }
}
