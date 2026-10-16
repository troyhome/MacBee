import XCTest
@testable import MacBeeAudio

final class AudioFormatInfoTests: XCTestCase {
    func testDisplayStrings() {
        XCTAssertEqual(AudioFormatInfo(codec: .flac, sourceSampleRate: 96_000, bitDepth: 24, channels: 2, isLossless: true)
            .displayString, "FLAC 24-bit / 96 kHz")
        XCTAssertEqual(AudioFormatInfo(codec: .alac, sourceSampleRate: 44_100, bitDepth: 16, channels: 2, isLossless: true)
            .displayString, "ALAC 16-bit / 44.1 kHz")
        XCTAssertEqual(AudioFormatInfo(codec: .mp3, sourceSampleRate: 44_100, bitDepth: nil, channels: 2, isLossless: false)
            .displayString, "MP3 44.1 kHz")
    }

    func testDSDNames() {
        XCTAssertEqual(AudioFormatInfo(codec: .dsd, sourceSampleRate: 2_822_400, bitDepth: 1, channels: 2, isLossless: true)
            .displayString, "DSD64")
        XCTAssertEqual(AudioFormatInfo(codec: .dsd, sourceSampleRate: 5_644_800, bitDepth: 1, channels: 2, isLossless: true)
            .dsdRateName, "DSD128")
    }

    func testALACFlags() {
        XCTAssertEqual(AudioFormatInfo.bitDepth(fromALACFlags: 1), 16)
        XCTAssertEqual(AudioFormatInfo.bitDepth(fromALACFlags: 3), 24)
        XCTAssertNil(AudioFormatInfo.bitDepth(fromALACFlags: 0))
    }

    func testSupportedExtensionsCoverRequiredFormats() {
        let ext = DecoderFactory.supportedExtensions
        for required in ["flac", "m4a", "wav", "aiff", "mp3", "dsf"] {
            XCTAssertTrue(ext.contains(required), "missing \(required)")
        }
    }
}
