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

    func testScanSortsSongs() {
        let a = track("Seagull", number: 1, size: 100)
        let b = track("Kaleidoscope", number: 2, size: 200)
        let c = track("Vapour Trail", number: 3, size: 300)
        let d = track("Polar Bear", number: 4, size: 400)
        let e = track("Dreams Burn Down", number: 5, size: 500)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let info = { (size: Int64) in DeviceSync.FileInfo(size: size, modified: old) }
        let existing: [String: DeviceSync.FileInfo] = [
            "Ride/Nowhere/01 - Seagull.flac": info(100),          // same: unchanged
            "Ride/Nowhere/02 - Kaleidoscope.flac": info(150),     // different size: changed
            "Ride/Nowhere/03 - Vapor Trail.flac": info(300),      // MacBee's, old title: moved
            "Their Folder/polar bear.flac": info(400),            // not MacBee's, same song: found elsewhere
            "Ride/Old/01 - Gone.flac": info(50),                  // MacBee's, not wanted: unneeded
            "Someone Else/Their.mp3": info(10),                   // not ours: left alone
        ]
        let tags: [String: (String, Double)] = [
            "Ride/Nowhere/03 - Vapor Trail.flac": (DeviceSync.songKey(artist: "Ride", title: "Vapour Trail", album: "Nowhere"), 200),
            "Their Folder/polar bear.flac": (DeviceSync.songKey(artist: "Ride", title: "Polar Bear", album: "Nowhere"), 200),
        ]
        let scan = DeviceSync.scan(sources: [.init(name: "Shoegaze", tracks: [a, b, c, d, e])], existing: existing,
                                   previousManifest: ["Ride/Old/01 - Gone.flac", "Ride/Nowhere/03 - Vapor Trail.flac"],
                                   sourceDate: { _ in old }, identify: { tags[$0].map { (key: $0.0, seconds: $0.1) } })
        XCTAssertEqual(scan.unchanged, 1)
        XCTAssertEqual(scan.changed.map(\.destination), ["Ride/Nowhere/02 - Kaleidoscope.flac"])
        XCTAssertEqual(scan.moved.map(\.replacing), ["Ride/Nowhere/03 - Vapor Trail.flac"])
        XCTAssertEqual(scan.foundElsewhere.map(\.replacing), ["Their Folder/polar bear.flac"])
        XCTAssertEqual(scan.newSongs.map(\.destination), ["Ride/Nowhere/05 - Dreams Burn Down.flac"])
        XCTAssertEqual(scan.unneeded, ["Ride/Old/01 - Gone.flac"])
        XCTAssertEqual(scan.otherFiles, 1)

        // Skipping songs found elsewhere: the playlist points at the file that's already there.
        var choices = DeviceSync.Choices()
        choices.elsewhere = .skip
        let job = DeviceSync.job(for: scan, choices: choices, device: "/D")
        XCTAssertEqual(job.playlists["Playlists/Shoegaze.m3u8"]?.contains("../Their Folder/polar bear.flac"), true)
        XCTAssertEqual(job.operations.count, 1 + 1 + 2 + 1) // new, changed, move (copy + remove), unneeded
        // A newer library file counts as changed even at the same size.
        let edited = DeviceSync.scan(sources: [.init(name: "", tracks: [a])], existing: existing, previousManifest: [],
                                     sourceDate: { _ in old.addingTimeInterval(60) }, identify: { _ in nil })
        XCTAssertEqual(edited.changed.count, 1)
    }

    func testJobCopiesPausesAndResumes() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("macbee-sync-\(UUID().uuidString)")
        let device = root.appendingPathComponent("device")
        try fm.createDirectory(at: device, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var songs: [Track] = []
        for n in 1...3 {
            let file = root.appendingPathComponent("song\(n).flac")
            try Data(repeating: UInt8(n), count: 100).write(to: file)
            songs.append(track("Song \(n)", number: n, size: 100, path: file.path))
        }
        func scanNow(_ tracks: [Track]) -> DeviceSync.Scan {
            let state = DeviceSync.inspect(device)
            return DeviceSync.scan(sources: [.init(name: "Mix", tracks: tracks)], existing: state.existing,
                                   previousManifest: state.manifest,
                                   sourceDate: { try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate },
                                   identify: { DeviceSync.identify(fileAt: device.appendingPathComponent($0)) })
        }
        var job = DeviceSync.job(for: scanNow(songs), choices: .init(), device: device.path)
        XCTAssertEqual(job.operations.count, 3)
        // Do one, "pause" (save and reload the job), then finish.
        try DeviceSync.perform(job.operations[0], in: &job)
        job.next = 1
        job = try JSONDecoder().decode(DeviceSync.Job.self, from: JSONEncoder().encode(job))
        while job.next < job.operations.count {
            try DeviceSync.perform(job.operations[job.next], in: &job)
            job.next += 1
        }
        DeviceSync.finish(job)
        XCTAssertEqual(job.report.copiedNew, 3)
        XCTAssertTrue(fm.fileExists(atPath: device.appendingPathComponent("Ride/Nowhere/01 - Song 1.flac").path))
        // Nothing to do the second time; dropping songs removes them and the empty folders.
        let again = scanNow(songs)
        XCTAssertEqual(again.unchanged, 3)
        XCTAssertTrue(again.newSongs.isEmpty && again.changed.isEmpty)
        var cleanup = DeviceSync.job(for: scanNow([]), choices: .init(), device: device.path)
        for operation in cleanup.operations { try DeviceSync.perform(operation, in: &cleanup) }
        XCTAssertEqual(cleanup.report.removed, 3)
        XCTAssertFalse(fm.fileExists(atPath: device.appendingPathComponent("Ride").path), "empty folders are cleaned up")
    }
}
