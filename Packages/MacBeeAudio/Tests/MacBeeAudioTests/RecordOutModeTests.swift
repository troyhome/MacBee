import XCTest
@testable import MacBeeAudio

final class RecordOutModeTests: XCTestCase {
    let typicalDAC: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]

    func testHiResIsCappedForMiniDisc() {
        let rates = RecordOutMode().allowedRates(typicalDAC)
        XCTAssertEqual(rates, [44_100, 48_000])
        XCTAssertEqual(SampleRatePolicy.bestRate(for: 88_200, supported: rates), 44_100)
        XCTAssertEqual(SampleRatePolicy.bestRate(for: 96_000, supported: rates), 48_000)
        XCTAssertEqual(SampleRatePolicy.bestRate(for: 44_100, supported: rates), 44_100)
    }

    func testNoCapKeepsEveryRate() {
        XCTAssertEqual(RecordOutMode(maxSampleRate: nil).allowedRates(typicalDAC), typicalDAC)
    }

    func testDeviceWithOnlyHighRatesFallsBackToAll() {
        XCTAssertEqual(RecordOutMode().allowedRates([96_000]), [96_000])
    }
}
