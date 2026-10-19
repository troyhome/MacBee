import XCTest
@testable import MacBeeLibrary

final class LyricsFinderTests: XCTestCase {
    func testTimedLyricsArePreferred() {
        let both = LyricsFinder.Record(duration: 200, instrumental: false, plainLyrics: "Hello", syncedLyrics: "[00:01.00]Hello")
        XCTAssertEqual(LyricsFinder.outcome(of: both), .found(.init(text: "[00:01.00]Hello", isTimed: true)))
        let plain = LyricsFinder.Record(duration: 200, instrumental: false, plainLyrics: "Hello", syncedLyrics: nil)
        XCTAssertEqual(LyricsFinder.outcome(of: plain), .found(.init(text: "Hello", isTimed: false)))
        let none = LyricsFinder.Record(duration: 200, instrumental: true, plainLyrics: nil, syncedLyrics: nil)
        XCTAssertEqual(LyricsFinder.outcome(of: none), .instrumental)
    }

    /// Talks to lrclib.net; skipped when MACBEE_ONLINE_TESTS isn't set.
    func testLiveLookup() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["MACBEE_ONLINE_TESTS"] == nil)
        let outcome = try await LyricsFinder.find(artist: "Ghinzu", title: "The Dragster-wave", album: "Blow", duration: 370)
        guard case let .found(found) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(found.text.contains("dragster wave"))
    }
}
