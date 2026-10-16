import XCTest
@testable import MacBeeAudio

final class OutputSettingsTests: XCTestCase {
    func testOldSavedSettingsStillLoad() throws {
        // Saved before loadIntoMemory existed.
        let json = #"{"deviceUID":"abc","exclusiveMode":true,"volumeMode":"hardware","softwareVolume":1,"dsdMode":"dop","preferHighestBitDepth":false}"#
        let settings = try JSONDecoder().decode(OutputSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.deviceUID, "abc")
        XCTAssertTrue(settings.exclusiveMode)
        XCTAssertEqual(settings.dsdMode, .dop)
        XCTAssertFalse(settings.preferHighestBitDepth)
        XCTAssertTrue(settings.loadIntoMemory)
    }

    func testRoundTrip() throws {
        var settings = OutputSettings.default
        settings.loadIntoMemory = false
        let copy = try JSONDecoder().decode(OutputSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(copy, settings)
    }
}
