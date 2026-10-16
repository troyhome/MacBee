import XCTest
@testable import MacBeeAudio

final class SampleRatePolicyTests: XCTestCase {
    let typicalDAC: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]

    func testExactMatchWins() {
        XCTAssertEqual(SampleRatePolicy.bestRate(for: 96_000, supported: typicalDAC), 96_000)
        XCTAssertEqual(SampleRatePolicy.bestRate(for: 44_100, supported: typicalDAC), 44_100)
    }

    func testUnsupportedRateStaysInSameFamily() {
        // 352.8k file on a 192k DAC -> 176.4k (same 44.1k family), not 192k.
        XCTAssertEqual(SampleRatePolicy.bestRate(for: 352_800, supported: typicalDAC), 176_400)
        XCTAssertEqual(SampleRatePolicy.bestRate(for: 384_000, supported: typicalDAC), 192_000)
    }

    func testFallsBackAcrossFamilies() {
        // Device that only does 48k.
        XCTAssertEqual(SampleRatePolicy.bestRate(for: 44_100, supported: [48_000]), 48_000)
    }

    func testEmptyDeviceList() {
        XCTAssertNil(SampleRatePolicy.bestRate(for: 44_100, supported: []))
    }

    func testExpandRanges() {
        let rates = SampleRatePolicy.expand(ranges: [(44_100, 44_100), (48_000, 96_000)])
        XCTAssertEqual(rates, [44_100, 48_000, 88_200, 96_000])
    }
}
