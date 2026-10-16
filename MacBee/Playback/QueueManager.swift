import Foundation
import MacBeeAudio
import MacBeeLibrary
import Observation

/// One entry in the queue. Its own id lets the same song appear twice and still be moved or removed on its own.
struct QueueItem: Identifiable, Hashable {
    let id = UUID()
    var track: Track
}

/// The play queue, with shuffle, repeat and an editable Up Next. The engine asks it for the next
/// track so it can pre-load it for gapless playback.
@MainActor
@Observable
final class QueueManager: PlaybackQueueSource {
    /// Play order (shuffled when shuffle is on).
    private(set) var items: [QueueItem] = []
    private(set) var currentIndex: Int? {
        didSet { rememberPlayed() }
    }
    /// Counts automatic moves to the next track, so a repeated track counts as a new play.
    private(set) var advanceCount = 0
    /// Songs played earlier in this session, newest first.
    private(set) var sessionHistory: [Track] = []

    private(set) var isShuffled: Bool {
        didSet { UserDefaults.standard.set(isShuffled, forKey: "shuffle") }
    }
    var repeatMode: RepeatMode {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode") }
    }

    /// Picks the file for each song (network drive or Plex copy). Set by AppModel.
    @ObservationIgnored weak var router: PlaybackRouter?

    /// The order the items were given in, restored when shuffle is turned off.
    @ObservationIgnored private var originalOrder: [QueueItem] = []

    init() {
        isShuffled = UserDefaults.standard.bool(forKey: "shuffle")
        repeatMode = UserDefaults.standard.string(forKey: "repeatMode").flatMap(RepeatMode.init) ?? .off
    }

    var tracks: [Track] { items.map(\.track) }
    var current: Track? { currentIndex.map { items[$0].track } }
    var hasNext: Bool { currentIndex.map { index(after: $0, userSkipped: true) != nil } ?? false }

    /// Everything after the current song, in play order.
    var upNext: [QueueItem] {
        guard let c = currentIndex else { return items }
        return Array(items[(c + 1)...])
    }

    // MARK: - Building the queue

    /// New queue starting at `index` of `tracks`. With shuffle on, that track plays first and the rest are shuffled.
    func replace(with tracks: [Track], startAt index: Int) {
        let newItems = tracks.map { QueueItem(track: $0) }
        originalOrder = newItems
        guard newItems.indices.contains(index) else {
            items = newItems
            currentIndex = nil
            return
        }
        if isShuffled {
            items = Self.shuffle(newItems, keepingFirst: newItems[index])
            currentIndex = 0
        } else {
            items = newItems
            currentIndex = index
        }
    }

    /// Turning shuffle on shuffles everything except the current track; turning it off restores the original order.
    func setShuffled(_ on: Bool) {
        guard on != isShuffled else { return }
        isShuffled = on
        let playing = currentIndex.map { items[$0] }
        if on {
            items = Self.shuffle(originalOrder, keepingFirst: playing)
            currentIndex = playing == nil ? nil : 0
        } else {
            items = originalOrder
            currentIndex = playing.flatMap { p in originalOrder.firstIndex { $0.id == p.id } }
        }
    }

    /// Inserts tracks right after the current one.
    func insertNext(_ tracks: [Track]) {
        guard let c = currentIndex else { return }
        let new = tracks.map { QueueItem(track: $0) }
        let currentId = items[c].id
        items.insert(contentsOf: new, at: c + 1)
        let o = originalOrder.firstIndex { $0.id == currentId }.map { $0 + 1 } ?? originalOrder.count
        originalOrder.insert(contentsOf: new, at: o)
    }

    /// Adds tracks to the end of the queue.
    func append(_ tracks: [Track]) {
        let new = tracks.map { QueueItem(track: $0) }
        items += new
        originalOrder += new
    }

    // MARK: - Editing Up Next (queue drawer)

    /// Moves Up Next entries. Offsets count from the first Up Next song.
    func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = (currentIndex ?? -1) + 1
        var next = Array(items[base...])
        next.move(fromOffsets: source, toOffset: destination)
        items.replaceSubrange(base..., with: next)
        if !isShuffled { originalOrder = items }
    }

    func removeFromUpNext(ids: Set<UUID>) {
        let base = (currentIndex ?? -1) + 1
        let kept = items[base...].filter { !ids.contains($0.id) }
        items.replaceSubrange(base..., with: kept)
        originalOrder.removeAll { ids.contains($0.id) }
    }

    func clearUpNext() {
        removeFromUpNext(ids: Set(upNext.map(\.id)))
    }

    /// Makes `index` the current track and returns it.
    func move(to index: Int) -> Track? {
        guard items.indices.contains(index) else { return nil }
        currentIndex = index
        return items[index].track
    }

    /// Jumps to an Up Next entry, by id.
    func move(toItem id: UUID) -> Track? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return move(to: index)
    }

    /// The position after `i`. Repeat One stays on the same track unless the user pressed Next.
    func index(after i: Int, userSkipped: Bool) -> Int? {
        if repeatMode == .one && !userSkipped { return i }
        if i + 1 < items.count { return i + 1 }
        return repeatMode == .all && !items.isEmpty ? 0 : nil
    }

    /// Replaces stored copies of a track (e.g. after toggling favorite).
    func update(_ track: Track) {
        for i in items.indices where items[i].track.id == track.id { items[i].track = track }
        for i in originalOrder.indices where originalOrder[i].track.id == track.id { originalOrder[i].track = track }
    }

    // MARK: - PlaybackQueueSource

    func track(after url: URL) -> URL? {
        guard let i = index(of: url), let next = index(after: i, userSkipped: false) else { return nil }
        let track = items[next].track
        return router.map { $0.readyURL(for: track) } ?? track.url
    }

    func engineDidAdvance(to url: URL) {
        if let i = index(of: url) { currentIndex = i }
        advanceCount += 1
    }

    // MARK: - Helpers

    /// Looks near the current position first, so a track that appears twice resolves correctly.
    private func index(of url: URL) -> Int? {
        func same(_ track: Track) -> Bool { router?.matches(track, url) ?? (track.url == url) }
        if let c = currentIndex {
            if same(items[c].track) { return c }
            if c + 1 < items.count, same(items[c + 1].track) { return c + 1 }
        }
        return items.firstIndex { same($0.track) }
    }

    /// The entry that was current, so we know what we just left.
    @ObservationIgnored private var lastCurrentItem: QueueItem?

    /// When the current entry changes, the one we left goes into this session's history.
    /// (Repeat One keeps the same entry, so it isn't added again.)
    private func rememberPlayed() {
        let newItem = currentIndex.map { items[$0] }
        if let old = lastCurrentItem, old.id != newItem?.id {
            sessionHistory.insert(old.track, at: 0)
            if sessionHistory.count > 50 { sessionHistory.removeLast() }
        }
        lastCurrentItem = newItem
    }

    private static func shuffle(_ items: [QueueItem], keepingFirst first: QueueItem?) -> [QueueItem] {
        var rest = items
        guard let first, let i = rest.firstIndex(where: { $0.id == first.id }) else { return rest.shuffled() }
        rest.remove(at: i)
        return [first] + rest.shuffled()
    }
}
