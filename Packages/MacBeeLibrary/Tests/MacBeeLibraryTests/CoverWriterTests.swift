import AVFoundation
import SFBAudioEngine
import XCTest
@testable import MacBeeLibrary

final class CoverWriterTests: XCTestCase {
    /// A tiny valid PNG (1 x 1 pixel).
    private let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func makeAIFF() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cover-\(UUID().uuidString).aiff")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsBigEndianKey: true, AVLinearPCMIsFloatKey: false,
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        try file.write(from: buffer)
        return url
    }

    func testEmbedsFrontCover() throws {
        let url = try makeAIFF()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(CoverWriter.embed(png, inFilesAt: [url.path]).isEmpty)
        let reread = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let covers = reread.metadata.attachedPictures(ofType: .frontCover)
        XCTAssertEqual(covers.count, 1)
        XCTAssertEqual(covers.first?.imageData, png)

        // Setting another cover replaces it instead of adding a second one.
        XCTAssertTrue(CoverWriter.embed(png, inFilesAt: [url.path]).isEmpty)
        XCTAssertEqual(try AudioFile(readingPropertiesAndMetadataFrom: url).metadata.attachedPictures(ofType: .frontCover).count, 1)
    }

    func testReportsUnreadableFiles() {
        let failures = CoverWriter.embed(png, inFilesAt: ["/nonexistent/song.flac"])
        XCTAssertEqual(failures.map(\.path), ["/nonexistent/song.flac"])
    }
}
