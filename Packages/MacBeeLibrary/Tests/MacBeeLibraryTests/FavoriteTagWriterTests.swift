import Foundation
import SFBAudioEngine
import XCTest
@testable import MacBeeLibrary

final class FavoriteTagWriterTests: XCTestCase {
    /// A short FLAC made from a system sound with macOS's own converter.
    private func makeFLAC() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let wav = dir.appendingPathComponent("fav-\(UUID().uuidString).wav")
        let flac = wav.deletingPathExtension().appendingPathExtension("flac")
        for args in [["-f", "WAVE", "-d", "LEI16", "/System/Library/Sounds/Ping.aiff", wav.path],
                     ["-f", "flac", "-d", "flac", wav.path, flac.path]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            process.arguments = args
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw XCTSkip("afconvert can't make FLAC here") }
        }
        try? FileManager.default.removeItem(at: wav)
        return flac
    }

    private func favorite(at url: URL) throws -> Bool? {
        FavoriteTagWriter.value(in: try AudioFile(readingPropertiesAndMetadataFrom: url).metadata)
    }

    func testWritesAndReadsTheHeart() throws {
        let url = try makeFLAC()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(try favorite(at: url))

        XCTAssertTrue(FavoriteTagWriter.write(true, toFilesAt: [url.path]).isEmpty)
        XCTAssertEqual(try favorite(at: url), true)

        XCTAssertTrue(FavoriteTagWriter.write(false, toFilesAt: [url.path]).isEmpty)
        XCTAssertEqual(try favorite(at: url), false)
    }

    func testSkipsFormatsThatCantHoldIt() {
        XCTAssertFalse(FavoriteTagWriter.canStore(path: "/a/b.mp3"))
        XCTAssertFalse(FavoriteTagWriter.canStore(path: "/a/b.m4a"))
        XCTAssertTrue(FavoriteTagWriter.canStore(path: "/a/b.FLAC"))
        XCTAssertTrue(FavoriteTagWriter.write(true, toFilesAt: ["/nonexistent/song.mp3"]).isEmpty)
    }
}
