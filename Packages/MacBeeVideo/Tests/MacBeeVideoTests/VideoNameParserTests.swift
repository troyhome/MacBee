import XCTest
@testable import MacBeeVideo

final class VideoNameParserTests: XCTestCase {
    func name(_ raw: String) -> VideoNameParser.Name { VideoNameParser.name(from: raw) }

    func testMovieNames() {
        XCTAssertEqual(name("Drive (2011) V2 (2160p BluRay x265 10bit HDR Tigole)"), .init(title: "Drive", year: 2011))
        XCTAssertEqual(name("The.Bridge.on.the.River.Kwai.1957.1080p.BluRay.x264.YIFY"),
                       .init(title: "The Bridge on the River Kwai", year: 1957))
        XCTAssertEqual(name("Big Fish (2003) {tmdb-587}"), .init(title: "Big Fish", year: 2003))
        XCTAssertEqual(name("(1982) Blade Runner"), .init(title: "Blade Runner", year: 1982))
        XCTAssertEqual(name("Stripes [1981] [2160p]"), .init(title: "Stripes", year: nil))
        XCTAssertEqual(name("Yesterday - 2019 "), .init(title: "Yesterday", year: 2019))
        XCTAssertEqual(name("Oblivion 2013"), .init(title: "Oblivion", year: 2013))
        XCTAssertEqual(name("Office Space (1999)"), .init(title: "Office Space", year: 1999))
        XCTAssertEqual(name("Wild.Target.2010.Retail.DKsubs.1080p.BluRay.x265.HEVC-HaNFuFu"),
                       .init(title: "Wild Target", year: 2010))
        XCTAssertEqual(name("Spies.Like.Us.1985.1080p.BluRay.H264.AAC-RARBG"), .init(title: "Spies Like Us", year: 1985))
        XCTAssertEqual(name("Mickey 17 (2025) [imdbid-tt12299608]"), .init(title: "Mickey 17", year: 2025))
        XCTAssertEqual(name("007 - Dr. No (1962) [1080p]"), .init(title: "Dr. No", year: 1962))
        XCTAssertEqual(name("01 Die Hard (1988)"), .init(title: "Die Hard", year: 1988))
    }

    func testEpisodes() {
        let a = VideoNameParser.episode(in: "Scrubs.(2026).-.S01E05.-.My.Angel")
        XCTAssertEqual(a?.season, 1)
        XCTAssertEqual(a?.episode, 5)
        XCTAssertEqual(a?.rest, "My Angel")
        let b = VideoNameParser.episode(in: "Band of Brothers (2001) - s01e02 - Day of Days - HDTV-1080p - h265")
        XCTAssertEqual(b, .init(season: 1, episode: 2, rest: "Day of Days"))
        let c = VideoNameParser.episode(in: "Scrubs (2026) - 2x01 - My First Time in a While")
        XCTAssertEqual(c, .init(season: 2, episode: 1, rest: "My First Time in a While"))
        XCTAssertEqual(VideoNameParser.episode(in: "Parks.and.Recreation.S07E12E13.One.Last.Ride")?.episode, 12)
        XCTAssertNil(VideoNameParser.episode(in: "Blade Runner 2049 (2017)"))
        XCTAssertNil(VideoNameParser.episode(in: "Mickey 17 (2025)"))
    }

    func testQuality() {
        XCTAssertTrue(VideoNameParser.is4K("Lawrence Of Arabia (1962) [2160p] [4K]"))
        XCTAssertFalse(VideoNameParser.is4K("Heathers (1988) [1080p]"))
        XCTAssertTrue(VideoNameParser.isHDR("Drive (2011) V2 (2160p BluRay x265 10bit HDR Tigole)"))
        XCTAssertFalse(VideoNameParser.isHDR("Jojo Rabbit (2019) [BluRay Rip 2160p"))
        XCTAssertTrue(VideoNameParser.isSample("Friends.Sample"))
    }

    func testShowTitles() {
        XCTAssertEqual(VideoScanner.showTitle(from: "Friends.Complete.Series.720p.BluRay.2CH.x265.HEVC-PSA").title, "Friends")
        XCTAssertEqual(VideoScanner.showTitle(from: "A.P.Bio.S02.COMPLETE.720p.AMZN.WEBRip.x264-GalaxyTV[TGx]").title, "A P Bio")
        XCTAssertEqual(VideoScanner.showTitle(from: "Community S3").title, "Community")
        XCTAssertEqual(VideoScanner.showTitle(from: "Scrubs (2026)"), .init(title: "Scrubs", year: 2026))
    }
}
