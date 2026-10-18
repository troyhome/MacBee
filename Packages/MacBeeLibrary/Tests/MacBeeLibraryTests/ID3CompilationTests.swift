import XCTest
@testable import MacBeeLibrary

final class ID3CompilationTests: XCTestCase {
    /// An ID3v2.3 tag body with one TCMP frame holding `text` (UTF-8).
    func tag(_ text: String) -> Data {
        let payload: [UInt8] = [3] + Array(text.utf8)
        let size = payload.count
        let header: [UInt8] = Array("TCMP".utf8) + [UInt8(size >> 24 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF), 0, 0]
        return Data(header + payload + [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) // + padding
    }

    func testZeroMeansNotACompilation() {
        XCTAssertEqual(ID3Compilation.compilation(inTag: tag("0"), version: 3, hasExtendedHeader: false), false)
        XCTAssertEqual(ID3Compilation.compilation(inTag: tag("1"), version: 3, hasExtendedHeader: false), true)
    }

    func testNoFrame() {
        XCTAssertNil(ID3Compilation.compilation(inTag: Data(repeating: 0, count: 20), version: 3, hasExtendedHeader: false))
    }

    func testRealMintzkovFileIfAvailable() throws {
        let url = URL(fileURLWithPath: "/Volumes/2 Set Music/Mintzkov/Sky Hits Ground/01 - 01 - Mintzkov - Slow Motion, Full Ahead.mp3")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(ID3Compilation.value(in: url), false)
    }
}
