import XCTest
@testable import MacBeeLibrary

final class SubsonicMatcherTests: XCTestCase {
    let local = [
        SubsonicMatcher.LocalSong(trackId: 1, relativePath: "Ride/Nowhere/01 Seagull.flac",
                                  artist: "Ride", title: "Seagull", album: "Nowhere", duration: 369),
        SubsonicMatcher.LocalSong(trackId: 2, relativePath: "Björk/Post/02 Hyperballad.flac",
                                  artist: "Björk", title: "Hyperballad", album: "Post", duration: 321),
        SubsonicMatcher.LocalSong(trackId: 3, relativePath: "Ride/Nowhere/02 Kaleidoscope.flac",
                                  artist: "Ride", title: "Kaleidoscope", album: "Nowhere", duration: 181),
    ]

    func testMatchesRealPaths() {
        let remote = [SubsonicMatcher.RemoteSong(id: "a", path: "/music/Ride/Nowhere/01 Seagull.flac",
                                                 artist: nil, title: nil, album: nil, duration: nil)]
        XCTAssertEqual(SubsonicMatcher.match(remote: remote, local: local), [1: "a"])
    }

    func testMatchesMadeUpPathsByTags() {
        // Navidrome's default made-up path doesn't match the files, so tags decide (accents and case ignored).
        let remote = [
            SubsonicMatcher.RemoteSong(id: "b", path: "Bjork/Post/02 - Hyperballad.flac",
                                       artist: "bjork", title: "Hyperballad", album: "Post", duration: 322),
            SubsonicMatcher.RemoteSong(id: "c", path: "Ride/Nowhere/02 - Kaleidoscope.flac",
                                       artist: "Ride", title: "Kaleidoscope", album: "Nowhere", duration: 250),
        ]
        // "c" is over a minute longer: a different recording, so not matched.
        XCTAssertEqual(SubsonicMatcher.match(remote: remote, local: local), [2: "b"])
    }
}
