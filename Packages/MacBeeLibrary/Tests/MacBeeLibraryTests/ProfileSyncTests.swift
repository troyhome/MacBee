import XCTest
@testable import MacBeeLibrary

final class ProfileSyncTests: XCTestCase {
    /// A library on "drive" with the same three songs.
    func library(drive: String) async throws -> (LibraryDatabase, [Int64]) {
        let db = try LibraryDatabase()
        let folder = try await db.insertFolder(path: "/Volumes/\(drive)", name: drive)
        let batch = (1...3).map { n -> ScannedTrack in
            var t = ScannedTrack(path: "/Volumes/\(drive)/Ride/Nowhere/0\(n).flac", fileSize: 1, modifiedAt: Date())
            t.title = "Song \(n)"; t.artist = "Ride"; t.album = "Nowhere"; t.duration = 200; t.codec = "FLAC"
            return t
        }
        _ = try await db.save(batch, folderId: folder.id!)
        let ids = try await db.search("Song").sorted { $0.path < $1.path }.compactMap(\.id)
        return (db, ids)
    }

    func testPlaysFavoritesAndPlaylistsMoveAcross() async throws {
        let (macA, a) = try await library(drive: "2 Set Music")
        let (macB, b) = try await library(drive: "Music Copy") // different drive name: matched by path below it
        let when = Date(timeIntervalSince1970: 1_760_000_000)
        try await macA.recordPlay(trackId: a[0], at: when)
        try await macA.setFavorite(trackId: a[1], true)
        let playlist = try await macA.createPlaylist(name: "Shoegaze")
        try await macA.addTracks([a[2], a[0]], toPlaylist: playlist.id!)

        let report = try await macB.mergeProfile(try await macA.profileSnapshot(deviceName: "A"))
        XCTAssertEqual(report.playsAdded, 1)
        XCTAssertEqual(report.favoritesAdded, 1)
        XCTAssertEqual(report.playlistsAdded, 1)
        XCTAssertEqual(report.playlistSongsAdded, 2)
        let song0 = try await macB.track(id: b[0])
        let song1 = try await macB.track(id: b[1])
        XCTAssertEqual(song0?.playCount, 1)
        XCTAssertEqual(song1?.isFavorite, true)

        // Syncing again adds nothing twice.
        let again = try await macB.mergeProfile(try await macA.profileSnapshot(deviceName: "A"))
        XCTAssertEqual(again, ProfileMergeReport())
    }

    func testMirrorReplacesPlaylistsAndFavorites() async throws {
        let (macA, a) = try await library(drive: "A")
        let (macB, b) = try await library(drive: "B")
        let mine = try await macA.createPlaylist(name: "Keep Me")
        try await macA.addTracks([a[0]], toPlaylist: mine.id!)
        _ = try await macB.createPlaylist(name: "Test Playlist on B")
        try await macB.setFavorite(trackId: b[2], true)

        _ = try await macB.mirrorProfile(try await macA.profileSnapshot(deviceName: "A"))
        let names = try await macB.playlists().map(\.name)
        XCTAssertEqual(names, ["Keep Me"])
        let unfavored = try await macB.track(id: b[2])
        XCTAssertEqual(unfavored?.isFavorite, false)
    }

    /// One automatic sync: A sends its data and base, B merges and applies, A applies the result.
    /// Returns each Mac's new base (its own data right after).
    func autoSync(_ macA: LibraryDatabase, _ macB: LibraryDatabase,
                  bases: (a: ProfileSnapshot?, b: ProfileSnapshot?)) async throws -> (a: ProfileSnapshot?, b: ProfileSnapshot?) {
        let mineA = try await macA.profileSnapshot(deviceName: "A")
        let mineB = try await macB.profileSnapshot(deviceName: "B")
        let merged = ProfileSnapshot.merged(mine: mineB, myBase: bases.b, theirs: mineA, theirBase: bases.a)
        _ = try await macB.applyProfile(merged, deleting: mineB.playlistKeysMissing(from: merged))
        _ = try await macA.applyProfile(merged, deleting: mineA.playlistKeysMissing(from: merged))
        return (try await macA.profileSnapshot(deviceName: "A"), try await macB.profileSnapshot(deviceName: "B"))
    }

    func testRemovalsCarryAcrossInAutomaticSync() async throws {
        let (macA, a) = try await library(drive: "A")
        let (macB, b) = try await library(drive: "B")
        try await macA.setFavorite(trackId: a[0], true)
        try await macA.setFavorite(trackId: a[1], true)
        let mix = try await macA.createPlaylist(name: "Mix")
        try await macA.addTracks([a[0], a[1], a[2]], toPlaylist: mix.id!)
        let gone = try await macA.createPlaylist(name: "Gone Soon")
        try await macA.addTracks([a[0]], toPlaylist: gone.id!)
        var bases = try await autoSync(macA, macB, bases: (nil, nil))
        let favoredOnB = try await macB.track(id: b[1])
        XCTAssertEqual(favoredOnB?.isFavorite, true)

        // A un-favorites a song, removes a song from Mix and deletes a playlist; B favorites another song.
        try await macA.setFavorite(trackId: a[1], false)
        let entries = try await macA.playlistEntries(playlistId: mix.id!)
        try await macA.removeEntries([entries[1].id], fromPlaylist: mix.id!)
        try await macA.deletePlaylist(id: gone.id!)
        try await macB.setFavorite(trackId: b[2], true)
        bases = try await autoSync(macA, macB, bases: bases)

        for (mac, ids) in [(macA, a), (macB, b)] {
            let favorites = try await [mac.track(id: ids[0]), mac.track(id: ids[1]), mac.track(id: ids[2])].map { $0?.isFavorite }
            XCTAssertEqual(favorites, [true, false, true])
            let names = try await mac.playlists().filter { !$0.isFolder }.map(\.name)
            XCTAssertEqual(names, ["Mix"])
            let mixId = try await mac.playlists().first { $0.name == "Mix" }!.id!
            let songs = try await mac.playlistEntries(playlistId: mixId).map(\.track.id)
            XCTAssertEqual(songs, [ids[0], ids[2]])
        }
        // Nothing left to do.
        let mineA = try await macA.profileSnapshot(deviceName: "A")
        let mineB = try await macB.profileSnapshot(deviceName: "B")
        let merged = ProfileSnapshot.merged(mine: mineB, myBase: bases.b, theirs: mineA, theirBase: bases.a)
        let report = try await macB.applyProfile(merged, deleting: mineB.playlistKeysMissing(from: merged))
        XCTAssertEqual(report, ProfileMergeReport())
    }

    /// A song only one Mac has must not look like a removal on the other.
    func testSongMissingOnOneMacIsNotRemoved() async throws {
        let (macA, a) = try await library(drive: "A")
        let (macB, _) = try await library(drive: "B")
        let extra = try await macA.insertFolder(path: "/Volumes/Extra", name: "Extra")
        var t = ScannedTrack(path: "/Volumes/Extra/Only/A.flac", fileSize: 1, modifiedAt: Date())
        t.title = "Only On A"; t.artist = "Solo"; t.album = "One"; t.duration = 100
        _ = try await macA.save([t], folderId: extra.id!)
        let onlyA = try await macA.search("Only On A").first!.id!
        try await macA.setFavorite(trackId: onlyA, true)
        try await macA.setFavorite(trackId: a[0], true)
        var bases = try await autoSync(macA, macB, bases: (nil, nil))
        bases = try await autoSync(macA, macB, bases: bases)
        bases = try await autoSync(macA, macB, bases: bases)
        let kept = try await macA.track(id: onlyA)
        XCTAssertEqual(kept?.isFavorite, true)
    }
}
