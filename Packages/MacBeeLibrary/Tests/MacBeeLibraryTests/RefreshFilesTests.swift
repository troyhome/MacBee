import XCTest
@testable import MacBeeLibrary

final class RefreshFilesTests: XCTestCase {
    /// A short, silent 16-bit stereo WAV file.
    private func writeWAV(to url: URL, seconds: Double = 0.1) throws {
        let rate = 44_100, channels = 2, bits = 16
        let frames = Int(Double(rate) * seconds)
        let dataSize = frames * channels * bits / 8
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataSize); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(channels); u32(rate)
        u32(rate * channels * bits / 8); u16(channels * bits / 8); u16(bits)
        d.append("data".data(using: .ascii)!); u32(dataSize); d.append(Data(count: dataSize))
        try d.write(to: url)
    }

    func testRefreshReadsOnlyTheGivenFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let music = root.appendingPathComponent("Music/Artist/Album", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let song = music.appendingPathComponent("01 Song.wav")
        try writeWAV(to: song)

        let library = try await MusicLibrary(location: LibraryLocation(directory: root.appendingPathComponent("Lib")))
        _ = try await library.database.insertFolder(path: root.appendingPathComponent("Music").standardizedFileURL.path,
                                                    name: "Music")
        let path = song.standardizedFileURL.path
        let saved = try await library.refreshFiles([path, "/elsewhere/not-in-library.wav"])
        XCTAssertEqual(saved, 1)
        let stats = try await library.database.stats()
        XCTAssertEqual(stats.tracks, 1)

        // Refreshing again updates the same song instead of adding a copy.
        _ = try await library.refreshFiles([path])
        let again = try await library.database.stats()
        XCTAssertEqual(again.tracks, 1)
    }

    /// A tag editor renamed and changed a song as it saved: re-reading the folder keeps it the same song.
    func testRenamedFileInSameFolderKeepsFavorite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let music = root.appendingPathComponent("Music/Artist/Album", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = music.appendingPathComponent("01 Song.wav")
        try writeWAV(to: old)
        let library = try await MusicLibrary(location: LibraryLocation(directory: root.appendingPathComponent("Lib")))
        _ = try await library.database.insertFolder(path: root.appendingPathComponent("Music").standardizedFileURL.path,
                                                    name: "Music")
        _ = try await library.refreshFiles([old.standardizedFileURL.path])
        let database = await library.database
        let id = try await database.tracks(matching: TrackFilter(), limit: 10).first!.id!
        try await library.database.setFavorite(trackId: id, true)

        // Renamed, and a little bigger (say, a cover was added).
        let renamed = music.appendingPathComponent("Song - Artist - 01.wav")
        try FileManager.default.moveItem(at: old, to: renamed)
        let handle = try FileHandle(forWritingTo: renamed)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(count: 64))
        try handle.close()

        let files = try await library.refreshDirectory(music.standardizedFileURL.path)
        XCTAssertEqual(files, [renamed.standardizedFileURL.path])
        let track = try await library.database.track(id: id)
        XCTAssertEqual(track?.path, renamed.standardizedFileURL.path)
        XCTAssertEqual(track?.isFavorite, true)
        XCTAssertEqual(track?.isMissing, false)
        let stats = try await library.database.stats()
        XCTAssertEqual(stats.tracks, 1)
    }
}
