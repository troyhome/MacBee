import XCTest
@testable import MacBeeLibrary

final class VolumeLocationTests: XCTestCase {
    func testMovingAFolderKeepsItsSongsAndFavorites() async throws {
        let db = try LibraryDatabase()
        let root = "/Volumes/2 Set Music"
        let folder = try await db.insertFolder(path: root, name: "2 Set Music")
        let batch = (1...2).map { n -> ScannedTrack in
            var t = ScannedTrack(path: "\(root)/Underworld/Café/0\(n).flac", fileSize: 1, modifiedAt: Date())
            t.title = "Song \(n)"; t.artist = "Underworld"; t.duration = 200; t.codec = "FLAC"
            return t
        }
        _ = try await db.save(batch, folderId: folder.id!)
        let ids = try await db.search("Song").sorted { $0.path < $1.path }.compactMap(\.id)
        try await db.setFavorite(trackId: ids[0], true)

        try await db.moveFolder(id: folder.id!, to: "/Volumes/2 Set Music-1")

        let folders = try await db.folders()
        XCTAssertEqual(folders.first?.path, "/Volumes/2 Set Music-1")
        let moved = try await db.search("Song").sorted { $0.path < $1.path }
        XCTAssertEqual(moved.map(\.path), ["/Volumes/2 Set Music-1/Underworld/Café/01.flac",
                                           "/Volumes/2 Set Music-1/Underworld/Café/02.flac"])
        XCTAssertEqual(moved.compactMap(\.id), ids)
        XCTAssertTrue(moved[0].isFavorite)
    }

    func testSameShareMatchesAcrossServerNamesButNotOtherShares() {
        let crusher = VolumeLocation.normalize(URL(string: "smb://troy@CRUSHER._smb._tcp.local/2%20Set%20Music")!)
        XCTAssertEqual(crusher, "smb://crusher/2 set music")
        XCTAssertTrue(VolumeLocation.sameVolume(crusher!, "smb://192.168.4.68/2 set music"))
        XCTAssertFalse(VolumeLocation.sameVolume(crusher!, "smb://crusher/movies shows"))
        XCTAssertFalse(VolumeLocation.sameVolume("uuid:A", "uuid:B"))
    }
}
