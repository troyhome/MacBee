import XCTest
@testable import MacBeeLibrary

final class HomeQueriesTests: XCTestCase {
    var db: LibraryDatabase!
    var folderId: Int64!

    override func setUp() async throws {
        db = try LibraryDatabase()
        folderId = try await db.insertFolder(path: "/M", name: "M").id
    }

    /// Adds `count` tracks on one album and returns their ids.
    @discardableResult
    func addAlbum(_ album: String, artist: String = "A", genre: String? = nil, year: Int? = nil,
                  count: Int = 1, bits: Int = 16, rate: Double = 44_100) async throws -> [Int64] {
        let batch = (1...count).map { n -> ScannedTrack in
            var t = ScannedTrack(path: "/M/\(artist)/\(album)/\(n).flac", fileSize: Int64(1000 + n),
                                 modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
            t.title = "\(album) \(n)"; t.artist = artist; t.album = album; t.trackNumber = n
            t.genre = genre; t.year = year; t.duration = 200; t.bitDepth = bits; t.sampleRate = rate; t.codec = "FLAC"
            return t
        }
        _ = try await db.save(batch, folderId: folderId)
        return try await db.search(album, limit: 1000).filter { $0.displayAlbum == album }.compactMap(\.id)
    }

    // MARK: History

    func testPlayHistoryIsNewestFirstAndPages() async throws {
        let ids = try await addAlbum("H", count: 3)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        for (i, id) in ids.enumerated() {
            try await db.recordPlay(trackId: id, at: base.addingTimeInterval(Double(i) * 60))
        }
        let firstPage = try await db.playHistory(limit: 2)
        XCTAssertEqual(firstPage.map(\.track.id), [ids[2], ids[1]])
        let next = try await db.playHistory(limit: 2, before: firstPage.last!.playedAt)
        XCTAssertEqual(next.map(\.track.id), [ids[0]])
    }

    func testHistoryGroupsByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_760_000_000) // a fixed "today"
        let track = Track(id: 1, folderId: 1, path: "/a", fileSize: 1, modifiedAt: now, title: nil, artist: nil,
                          albumArtist: nil, album: nil, genre: nil, composer: nil, year: nil, trackNumber: nil,
                          trackTotal: nil, discNumber: nil, discTotal: nil, isCompilation: false, duration: 1,
                          sampleRate: nil, bitDepth: nil, channels: nil, bitrate: nil, codec: "FLAC",
                          displayAlbum: "", displayAlbumArtist: "", albumKey: "", artistKey: "", artworkId: nil,
                          dateAdded: now, playCount: 0, lastPlayedAt: nil, isFavorite: false, rating: nil, isMissing: false)
        let entries = [0.0, -3_600, -86_400, -86_400 * 5].enumerated().map { i, offset in
            PlayHistoryEntry(playId: Int64(i), playedAt: now.addingTimeInterval(offset), track: track)
        }
        let days = PlayHistory.groupByDay(entries, now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.title).prefix(2), ["Today", "Yesterday"])
        XCTAssertEqual(days.map(\.entries.count), [2, 1, 1])
    }

    // MARK: Forgotten gems

    func testForgottenGems() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let old = now.addingTimeInterval(-86_400 * 250)    // ~8 months ago
        let recent = now.addingTimeInterval(-86_400 * 10)

        let loved = try await addAlbum("Loved Long Ago")
        for _ in 0..<3 { try await db.recordPlay(trackId: loved[0], at: old) }

        let current = try await addAlbum("Still Playing")
        for _ in 0..<3 { try await db.recordPlay(trackId: current[0], at: recent) }

        let favorite = try await addAlbum("Favorite Never Played")
        try await db.setFavorite(trackId: favorite[0], true)

        try await addAlbum("Never Played")

        let gems = try await db.forgottenGems(now: now)
        XCTAssertEqual(Set(gems.map(\.title)), ["Loved Long Ago", "Favorite Never Played"])
    }

    // MARK: Mixes

    func testMixesPickTopGenreDecadeHiResAndFavorites() async throws {
        try await addAlbum("Jazz Record", genre: "Jazz", year: 1965, count: 25)
        let rock = try await addAlbum("Rock Record", genre: "rock", year: 1994, count: 12, bits: 24, rate: 96_000)
        for id in rock.prefix(5) { try await db.setFavorite(trackId: id, true) }
        for id in rock.prefix(6) { try await db.recordPlay(trackId: id) }

        let mixes = try await db.suggestedMixes(day: 100)
        XCTAssertEqual(mixes.map(\.kind), [.mostPlayed, .genre("Jazz"), .decade(1960), .hiRes, .favorites])
        XCTAssertEqual(mixes.first { $0.kind == .hiRes }?.tracks.count, 12)
        XCTAssertEqual(mixes.first { $0.kind == .decade(1960) }?.tracks.allSatisfy { $0.year == 1965 }, true)
    }

    func testMixOrderIsStableForADayAndChangesNextDay() async throws {
        try await addAlbum("Jazz Record", genre: "Jazz", count: 30)
        let today1 = try await db.suggestedMixes(day: 500).first { $0.kind == .genre("Jazz") }!.tracks.map(\.id)
        let today2 = try await db.suggestedMixes(day: 500).first { $0.kind == .genre("Jazz") }!.tracks.map(\.id)
        let tomorrow = try await db.suggestedMixes(day: 501).first { $0.kind == .genre("Jazz") }!.tracks.map(\.id)
        XCTAssertEqual(today1, today2)
        XCTAssertNotEqual(today1, tomorrow)
    }
}
