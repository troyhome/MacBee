import XCTest
@testable import MacBeeAudio

final class EqualizerTests: XCTestCase {
    func testOffByDefaultAndInactive() {
        let eq = EqualizerSettings()
        XCTAssertFalse(eq.isEnabled)
        XCTAssertFalse(eq.isActive)
        XCTAssertEqual(eq.gains.count, 16)
    }

    func testOnButFlatIsNotActive() {
        var eq = EqualizerSettings(isEnabled: true)
        XCTAssertFalse(eq.isActive)
        eq.apply(.flat)
        XCTAssertFalse(eq.isActive)
        eq.apply(.punchy)
        XCTAssertTrue(eq.isActive)
        eq.isEnabled = false
        XCTAssertFalse(eq.isActive)
    }

    func testPreampAloneMakesItActive() {
        let eq = EqualizerSettings(isEnabled: true, preamp: -2)
        XCTAssertTrue(eq.isActive)
    }

    func testGainsAreClampedAndPadded() {
        let eq = EqualizerSettings(isEnabled: true, preamp: 40, gains: [30, -30])
        XCTAssertEqual(eq.preamp, 12)
        XCTAssertEqual(eq.gains.count, 16)
        XCTAssertEqual(eq.gains[0], 12)
        XCTAssertEqual(eq.gains[1], -12)
        XCTAssertEqual(eq.gains[2], 0)
    }

    func testBuiltInPresets() {
        XCTAssertEqual(EqualizerPreset.builtIns.map(\.name), ["Flat", "Typical", "Punchy", "Reduce Treble", "Brite", "Indie"])
        XCTAssertEqual(Set(EqualizerPreset.builtIns.map(\.id)).count, 6)
        for preset in EqualizerPreset.builtIns {
            XCTAssertEqual(preset.gains.count, 16, preset.name)
            XCTAssertTrue(preset.isBuiltIn)
        }
        var eq = EqualizerSettings(isEnabled: true)
        eq.apply(.brite)
        XCTAssertTrue(eq.matches(.brite))
        XCTAssertFalse(eq.matches(.punchy))
    }

    func testOldSavedSettingsDecode() throws {
        let data = Data(#"{"isEnabled":true}"#.utf8)
        let eq = try JSONDecoder().decode(EqualizerSettings.self, from: data)
        XCTAssertTrue(eq.isEnabled)
        XCTAssertEqual(eq.gains.count, 16)
        XCTAssertTrue(eq.isFlat)
    }

    func testActiveEqualizerBreaksBitPerfect() {
        let format = AudioFormatInfo(codec: .flac, sourceSampleRate: 44_100, bitDepth: 16, channels: 2, isLossless: true)
        func status(_ eq: Bool) -> SignalPathStatus {
            .evaluate(.init(format: format, dsdMode: .dop, deviceSampleRate: 44_100, deviceBitDepth: 24,
                            volumeMode: .hardware, softwareVolume: 1, exclusiveMode: true, equalizerActive: eq))
        }
        XCTAssertTrue(status(false).isBitPerfect)
        XCTAssertEqual(status(true).issues, [.equalizer])
    }
}
