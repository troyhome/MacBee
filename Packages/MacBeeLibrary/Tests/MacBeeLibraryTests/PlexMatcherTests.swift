import XCTest
@testable import MacBeeLibrary

final class PlexMatcherTests: XCTestCase {
    func testMatchesAcrossDifferentStartingFolders() {
        let local = [
            PlexMatcher.LocalFile(trackId: 1, relativePath: "Björk/Debut/01 Human Behaviour.flac"),
            PlexMatcher.LocalFile(trackId: 2, relativePath: "Garbage/Garbage/02 Queer.flac"),
            PlexMatcher.LocalFile(trackId: 3, relativePath: "Only Local/Album/01.flac"),
        ]
        let plex = [
            // Same files on a NAS, under another folder; accent stored decomposed; different capitals.
            PlexMatcher.PlexFile(path: "/volume1/2 Set Music/Bjo\u{0308}rk/Debut/01 Human Behaviour.flac", partKey: "/library/parts/10/a/file.flac"),
            PlexMatcher.PlexFile(path: "/volume1/2 Set Music/GARBAGE/Garbage/02 Queer.flac", partKey: "/library/parts/11/b/file.flac"),
            PlexMatcher.PlexFile(path: "/volume1/2 Set Music/Only On Plex/x.flac", partKey: "/library/parts/12/c/file.flac"),
        ]
        let links = PlexMatcher.match(plexFiles: plex, localFiles: local)
        XCTAssertEqual(links, [1: "/library/parts/10/a/file.flac", 2: "/library/parts/11/b/file.flac"])
    }

    func testLinksAreStored() async throws {
        let db = try LibraryDatabase()
        let folderId = try await db.insertFolder(path: "/Volumes/2 Set Music", name: "2 Set Music").id!
        var t = ScannedTrack(path: "/Volumes/2 Set Music/A/B/01.flac", fileSize: 1, modifiedAt: Date())
        t.title = "One"; t.codec = "FLAC"
        _ = try await db.save([t], folderId: folderId)

        let files = try await db.localFilesForMatching()
        XCTAssertEqual(files.map(\.relativePath), ["A/B/01.flac"])
        let links = PlexMatcher.match(plexFiles: [.init(path: "/data/music/A/B/01.flac", partKey: "/p/1")], localFiles: files)
        try await db.replacePlexLinks(links)
        let count = try await db.plexLinkCount()
        XCTAssertEqual(count, 1)
        let key = try await db.plexPartKey(trackId: files[0].trackId)
        XCTAssertEqual(key, "/p/1")
    }
}
