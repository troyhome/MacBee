import XCTest
@testable import MacBeeLibrary

final class Phase4Tests: XCTestCase {
    func track(_ title: String, number: Int, album: String = "Nowhere", artist: String = "Ride", size: Int64 = 100,
               path: String? = nil) -> Track {
        Track(id: Int64(number), folderId: 1, path: path ?? "/M/\(artist)/\(album)/\(number).flac", fileSize: size,
              modifiedAt: Date(), title: title, artist: artist, albumArtist: nil, album: album, genre: nil, composer: nil,
              year: nil, trackNumber: number, trackTotal: nil, discNumber: nil, discTotal: nil, isCompilation: false,
              duration: 200, sampleRate: nil, bitDepth: nil, channels: nil, bitrate: nil, codec: "FLAC",
              displayAlbum: album, displayAlbumArtist: artist, albumKey: "", artistKey: "", artworkId: nil,
              dateAdded: Date(), playCount: 0, lastPlayedAt: nil, isFavorite: false, rating: nil, isMissing: false)
    }

    func testLRCParsing() {
        let text = """
            [ar:Ride]
            [offset:+500]
            [00:12.50]First line
            [00:20.00][01:20.00]Chorus
            not a lyric line
            """
        let lines = LRCParser.parse(text)
        XCTAssertEqual(lines.map(\.text), ["First line", "Chorus", "Chorus"])
        XCTAssertEqual(lines[0].time, 12.0, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 79.5, accuracy: 0.001)
        XCTAssertEqual(Lyrics.currentLine(in: lines, at: 25), 1)
        XCTAssertNil(Lyrics.currentLine(in: lines, at: 5))
    }

    func testEstimatedTimingSpreadsLines() {
        let lines = LyricsReader.estimatedTiming("One\n\nTwo\nThree", duration: 100)
        XCTAssertEqual(lines.map(\.text), ["One", "Two", "Three"])
        XCTAssertEqual(lines[0].time, 6, accuracy: 0.01)
        XCTAssertLessThan(lines[2].time, 92)
    }

    func testDevicePathNaming() {
        XCTAssertEqual(DeviceSync.devicePath(for: track("Seagull", number: 1)), "Ride/Nowhere/01 - Seagull.flac")
        XCTAssertEqual(DeviceSync.devicePath(for: track("What? / Why", number: 12)), "Ride/Nowhere/12 - What_ _ Why.flac")
    }

    func testPlanCopiesOnlyChangesAndPrunes() {
        let a = track("Seagull", number: 1, size: 100)
        let b = track("Kaleidoscope", number: 2, size: 200)
        let source = DeviceSync.Source(name: "Shoegaze", tracks: [a, b])
        let existing: [String: Int64] = ["Ride/Nowhere/01 - Seagull.flac": 100,      // same: skip
                                         "Ride/Old/01 - Gone.flac": 50,               // MacBee put it there: remove
                                         "Someone Else/Their.mp3": 10]                // not ours: leave alone
        let plan = DeviceSync.plan(sources: [source], existing: existing,
                                   previousManifest: ["Ride/Old/01 - Gone.flac", "Ride/Nowhere/01 - Seagull.flac"])
        XCTAssertEqual(plan.unchanged, 1)
        XCTAssertEqual(plan.copies.map(\.destination), ["Ride/Nowhere/02 - Kaleidoscope.flac"])
        XCTAssertEqual(plan.removals, ["Ride/Old/01 - Gone.flac"])
        XCTAssertEqual(plan.playlists["Playlists/Shoegaze.m3u8"]?.contains("../Ride/Nowhere/02 - Kaleidoscope.flac"), true)
    }

    func testRunCopiesIntoAFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("macbee-sync-\(UUID().uuidString)")
        let device = root.appendingPathComponent("device")
        try fm.createDirectory(at: device, withIntermediateDirectories: true)
        let sourceFile = root.appendingPathComponent("song.flac")
        try Data(repeating: 1, count: 100).write(to: sourceFile)
        defer { try? fm.removeItem(at: root) }
        let song = track("Seagull", number: 1, size: 100, path: sourceFile.path)
        var state = DeviceSync.inspect(device)
        var plan = DeviceSync.plan(sources: [.init(name: "Mix", tracks: [song])], existing: state.existing, previousManifest: state.manifest)
        let first = DeviceSync.run(plan, to: device)
        XCTAssertEqual(first.copied, 1)
        XCTAssertTrue(fm.fileExists(atPath: device.appendingPathComponent("Ride/Nowhere/01 - Seagull.flac").path))
        // Second time: nothing to copy. Then drop the song: it's removed.
        state = DeviceSync.inspect(device)
        plan = DeviceSync.plan(sources: [.init(name: "Mix", tracks: [song])], existing: state.existing, previousManifest: state.manifest)
        XCTAssertTrue(plan.copies.isEmpty)
        plan = DeviceSync.plan(sources: [.init(name: "Mix", tracks: [])], existing: state.existing, previousManifest: state.manifest)
        let third = DeviceSync.run(plan, to: device)
        XCTAssertEqual(third.removed, 1)
        XCTAssertFalse(fm.fileExists(atPath: device.appendingPathComponent("Ride").path), "empty folders are cleaned up")
    }
}
