import XCTest
@testable import MacBeeAudio

final class SignalPathTests: XCTestCase {
    let flac24_96 = AudioFormatInfo(codec: .flac, sourceSampleRate: 96_000, bitDepth: 24, channels: 2, isLossless: true)
    let dsd64DoP = AudioFormatInfo(codec: .dsd, sourceSampleRate: 2_822_400, bitDepth: 1, channels: 2,
                                   isLossless: true, deliveredSampleRate: 176_400)

    private func input(_ format: AudioFormatInfo, rate: Double, bits: Int? = 24,
                       volumeMode: VolumeMode = .hardware, softwareVolume: Float = 1,
                       dsd: DSDPlaybackMode = .dop, exclusive: Bool = true) -> SignalPathStatus.Input {
        .init(format: format, dsdMode: dsd, deviceSampleRate: rate, deviceBitDepth: bits,
              volumeMode: volumeMode, softwareVolume: softwareVolume, exclusiveMode: exclusive)
    }

    func testMatchedRateAndDepthIsBitPerfect() {
        let s = SignalPathStatus.evaluate(input(flac24_96, rate: 96_000))
        XCTAssertTrue(s.isBitPerfect)
        XCTAssertTrue(s.notes.isEmpty)
    }

    func testRateMismatchIsFlagged() {
        let s = SignalPathStatus.evaluate(input(flac24_96, rate: 48_000))
        XCTAssertEqual(s.issues, [.resampled(from: 96_000, to: 48_000)])
    }

    func testSoftwareVolumeBelowFullIsFlagged() {
        let s = SignalPathStatus.evaluate(input(flac24_96, rate: 96_000, volumeMode: .software, softwareVolume: 0.5))
        XCTAssertEqual(s.issues, [.softwareVolume(0.5)])
        let full = SignalPathStatus.evaluate(input(flac24_96, rate: 96_000, volumeMode: .software, softwareVolume: 1))
        XCTAssertTrue(full.isBitPerfect)
    }

    func testVirtualDeviceIsNeverBitPerfect() {
        var i = input(flac24_96, rate: 96_000)
        i.isVirtualDevice = true
        XCTAssertEqual(SignalPathStatus.evaluate(i).issues, [.virtualDevice])
    }

    func testBitDepthReduction() {
        let s = SignalPathStatus.evaluate(input(flac24_96, rate: 96_000, bits: 16))
        XCTAssertEqual(s.issues, [.bitDepthReduced(from: 24, to: 16)])
    }

    func testDoPIsBitPerfectAtCarrierRate() {
        XCTAssertTrue(SignalPathStatus.evaluate(input(dsd64DoP, rate: 176_400)).isBitPerfect)
    }

    func testDSDToPCMIsNotBitPerfect() {
        let s = SignalPathStatus.evaluate(input(dsd64DoP, rate: 176_400, dsd: .pcmConversion))
        XCTAssertTrue(s.issues.contains(.dsdConvertedToPCM))
    }

    func testSharedModeIsANoteNotAnIssue() {
        let s = SignalPathStatus.evaluate(input(flac24_96, rate: 96_000, exclusive: false))
        XCTAssertTrue(s.isBitPerfect)
        XCTAssertEqual(s.notes, [.sharedMode])
    }
}
