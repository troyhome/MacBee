import XCTest
@testable import MacBeeLibrary

final class ScanPlannerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func stamp(_ size: Int64, _ offset: TimeInterval = 0) -> FileStamp {
        FileStamp(size: size, modified: t0.addingTimeInterval(offset))
    }

    func testNewChangedUnchanged() {
        let existing = [
            "/m/a.flac": ExistingFile(id: 1, stamp: stamp(100), isMissing: false),
            "/m/b.flac": ExistingFile(id: 2, stamp: stamp(200), isMissing: false),
        ]
        let found = [
            "/m/a.flac": stamp(100),        // unchanged
            "/m/b.flac": stamp(250, 60),    // retagged
            "/m/c.flac": stamp(300),        // new
        ]
        let plan = ScanPlanner.plan(existing: existing, found: found)
        XCTAssertEqual(plan.toRead, ["/m/b.flac", "/m/c.flac"])
        XCTAssertEqual(plan.unchanged, 1)
        XCTAssertTrue(plan.missing.isEmpty)
    }

    func testForceRescanRereadsUnchangedFiles() {
        let existing = [
            "/m/a.flac": ExistingFile(id: 1, stamp: stamp(100), isMissing: false),
            "/m/b.flac": ExistingFile(id: 2, stamp: stamp(200), isMissing: true),
            "/m/gone.flac": ExistingFile(id: 3, stamp: stamp(300), isMissing: false),
        ]
        let found = ["/m/a.flac": stamp(100), "/m/b.flac": stamp(200)]
        let plan = ScanPlanner.plan(existing: existing, found: found, rereadAll: true)
        XCTAssertEqual(plan.toRead, ["/m/a.flac", "/m/b.flac"])
        XCTAssertEqual(plan.unchanged, 0)
        XCTAssertEqual(plan.restored, [2])
        XCTAssertEqual(plan.missing, [3])
    }

    func testSmallTimestampDifferenceIsIgnored() {
        let existing = ["/m/a.flac": ExistingFile(id: 1, stamp: stamp(100), isMissing: false)]
        let plan = ScanPlanner.plan(existing: existing, found: ["/m/a.flac": stamp(100, 1.5)])
        XCTAssertEqual(plan.unchanged, 1)
        XCTAssertTrue(plan.toRead.isEmpty)
    }

    func testRemovedFilesAreFlaggedMissing() {
        let existing = [
            "/m/a.flac": ExistingFile(id: 1, stamp: stamp(100), isMissing: false),
            "/m/b.flac": ExistingFile(id: 2, stamp: stamp(200), isMissing: false),
        ]
        let plan = ScanPlanner.plan(existing: existing, found: ["/m/a.flac": stamp(100)])
        XCTAssertEqual(plan.missing, [2])
    }

    func testEmptyFolderDoesNotWipeLibrary() {
        let existing = ["/m/a.flac": ExistingFile(id: 1, stamp: stamp(100), isMissing: false)]
        let plan = ScanPlanner.plan(existing: existing, found: [:])
        XCTAssertTrue(plan.skippedRemovals)
        XCTAssertTrue(plan.missing.isEmpty)
    }

    func testMissingFileThatReturnsIsRestored() {
        let existing = ["/m/a.flac": ExistingFile(id: 7, stamp: stamp(100), isMissing: true)]
        let plan = ScanPlanner.plan(existing: existing, found: ["/m/a.flac": stamp(100)])
        XCTAssertEqual(plan.restored, [7])
        XCTAssertTrue(plan.toRead.isEmpty)
    }
}
