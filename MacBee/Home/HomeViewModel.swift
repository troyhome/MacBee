import Foundation
import MacBeeLibrary
import Observation

/// Everything on the Home (Music) screen, loaded together.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var recentlyPlayed: [AlbumSummary] = []
    private(set) var recentlyAdded: [AlbumSummary] = []
    private(set) var mixes: [Mix] = []
    private(set) var forgottenGems: [AlbumSummary] = []
    private(set) var history: [PlayHistoryEntry] = []
    private(set) var historyDays: [PlayHistoryDay] = []
    private(set) var canLoadMoreHistory = false
    private(set) var isLoaded = false

    private static let historyPageSize = 60

    func load(from database: LibraryDatabase) async {
        async let played = database.albums(sortedBy: .recentlyPlayed, limit: 20)
        async let added = database.albums(sortedBy: .recentlyAdded, limit: 20)
        async let mixes = database.suggestedMixes(day: SuggestedMixes.day)
        async let gems = database.forgottenGems()
        async let history = database.playHistory(limit: Self.historyPageSize)

        // "Clear" and "Reset" on the Music page hide what came before that moment (nothing is deleted).
        let playedCutoff = UserDefaults.standard.object(forKey: "homeRecentlyPlayedClearedAt") as? Date ?? .distantPast
        let addedCutoff = UserDefaults.standard.object(forKey: "homeRecentlyAddedResetAt") as? Date ?? .distantPast
        recentlyPlayed = ((try? await played) ?? []).filter { ($0.lastPlayedAt ?? .distantPast) > playedCutoff }
        recentlyAdded = ((try? await added) ?? []).filter { $0.dateAdded > addedCutoff }
        self.mixes = (try? await mixes) ?? []
        forgottenGems = (try? await gems) ?? []
        setHistory((try? await history) ?? [])
        isLoaded = true
    }

    /// Empties Recently Played (albums played from now on show up again).
    func clearRecentlyPlayed() {
        UserDefaults.standard.set(Date(), forKey: "homeRecentlyPlayedClearedAt")
        recentlyPlayed = []
    }

    /// Empties Recently Added (music added from now on shows up).
    func resetRecentlyAdded() {
        UserDefaults.standard.set(Date(), forKey: "homeRecentlyAddedResetAt")
        recentlyAdded = []
    }

    /// Deletes the play history list (play counts stay).
    func resetPlayHistory(in database: LibraryDatabase) async {
        try? await database.deletePlayHistory()
        setHistory([])
    }

    /// Rebuilds the suggested mixes with new songs.
    func refreshMixes(from database: LibraryDatabase) async {
        SuggestedMixes.reshuffle()
        mixes = (try? await database.suggestedMixes(day: SuggestedMixes.day)) ?? mixes
    }

    func loadMoreHistory(from database: LibraryDatabase) async {
        guard let oldest = history.last?.playedAt,
              let more = try? await database.playHistory(limit: Self.historyPageSize, before: oldest) else { return }
        setHistory(history + more, lastPageCount: more.count)
    }

    private func setHistory(_ entries: [PlayHistoryEntry], lastPageCount: Int? = nil) {
        history = entries
        historyDays = PlayHistory.groupByDay(entries)
        canLoadMoreHistory = (lastPageCount ?? entries.count) == Self.historyPageSize
    }
}

/// Which shuffle of today's suggested mixes is showing, so the Media page and Playlist Studio show the same mixes.
enum SuggestedMixes {
    private static let key = "suggestedMixesShuffle"

    /// Today's mixes, moved on by each Refresh Suggestions (back to the plain day's shuffle tomorrow).
    static var day: Int {
        let today = LibraryDatabase.dayNumber()
        let saved = UserDefaults.standard.dictionary(forKey: key)
        let offset = (saved?["day"] as? Int) == today ? (saved?["offset"] as? Int ?? 0) : 0
        return today + offset * 7919
    }

    static func reshuffle() {
        let today = LibraryDatabase.dayNumber()
        let saved = UserDefaults.standard.dictionary(forKey: key)
        let offset = (saved?["day"] as? Int) == today ? (saved?["offset"] as? Int ?? 0) : 0
        UserDefaults.standard.set(["day": today, "offset": offset + 1], forKey: key)
    }
}
