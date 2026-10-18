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
    /// Bumped by Refresh Suggestions: a different shuffle than today's.
    private var shuffleOffset = 0

    func load(from database: LibraryDatabase) async {
        async let played = database.albums(sortedBy: .recentlyPlayed, limit: 20)
        async let added = database.albums(sortedBy: .recentlyAdded, limit: 20)
        async let mixes = database.suggestedMixes(day: LibraryDatabase.dayNumber() + shuffleOffset * 7919)
        async let gems = database.forgottenGems()
        async let history = database.playHistory(limit: Self.historyPageSize)

        recentlyPlayed = (try? await played) ?? []
        recentlyAdded = (try? await added) ?? []
        self.mixes = (try? await mixes) ?? []
        forgottenGems = (try? await gems) ?? []
        setHistory((try? await history) ?? [])
        isLoaded = true
    }

    /// Rebuilds the suggested mixes with new songs.
    func refreshMixes(from database: LibraryDatabase) async {
        shuffleOffset += 1
        mixes = (try? await database.suggestedMixes(day: LibraryDatabase.dayNumber() + shuffleOffset * 7919)) ?? mixes
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
