import Foundation
import MacBeeLibrary
@preconcurrency import Network
import Observation

/// Keeps two MacBees on the same network in step (roadmap Phase 5): play counts and history, favorites,
/// ratings and playlists. Each Mac with "Sync with my other Macs" on announces itself on the local network
/// (Bonjour) and shows a 6-digit code; the other Mac enters that code once, then "Sync Now" swaps everything
/// both ways. Nothing is ever deleted by a sync. Music files are not copied: both Macs need the same music.
/// After two Macs have synced once, they keep each other up to date automatically (see "Automatic sync").
@MainActor
@Observable
final class NetworkSync {
    struct Peer: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    static let serviceType = "_macbee-sync._tcp"

    /// How two Macs are brought together. Plays and history are always combined (they really happened).
    enum Mode: String, Codable, CaseIterable, Identifiable {
        /// Everything from both Macs ends up on both; nothing is deleted.
        case combine
        /// The other Mac's favorites and playlists are replaced by this Mac's.
        case sendMine
        /// This Mac's favorites and playlists are replaced by the other Mac's.
        case takeTheirs
        /// The automatic sync between Macs that synced before: whichever Mac changed something wins, removals too.
        case automatic
        var id: String { rawValue }
    }

    private(set) var peers: [Peer] = []
    private(set) var syncingWith: String?
    /// The result of the last sync (either direction).
    private(set) var lastMessage: String?
    /// Playlists deleted on the other Mac that still exist here: asked about in the main window.
    var pendingRemovals: [(removed: ProfileSnapshot.RemovedPlaylist, playlistId: Int64)] = []
    /// The Mac those deletions came from.
    private(set) var pendingRemovalsFrom = ""

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: "networkSyncEnabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "networkSyncEnabled")
            isEnabled ? start() : stop()
        }
    }

    /// The code another Mac must enter to sync with this one.
    let code: String = {
        if let saved = UserDefaults.standard.string(forKey: "networkSyncCode") { return saved }
        let made = String(format: "%06d", Int.random(in: 0...999_999))
        UserDefaults.standard.set(made, forKey: "networkSyncCode")
        return made
    }()

    let deviceName = Host.current().localizedName ?? "Mac"

    /// After the first sync, changes go across on their own whenever both Macs have MacBee open.
    var syncsAutomatically: Bool = UserDefaults.standard.object(forKey: "networkSyncAuto") as? Bool ?? true {
        didSet { UserDefaults.standard.set(syncsAutomatically, forKey: "networkSyncAuto") }
    }

    @ObservationIgnored private let library: MusicLibrary
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var browser: NWBrowser?
    /// Called after another Mac's data was added here (to refresh playlists and lists).
    @ObservationIgnored var onMerged: (() async -> Void)?
    /// Liked videos, by name (from the Videos library), and setting them after a sync.
    @ObservationIgnored var likedVideos: (() -> [String])?
    @ObservationIgnored var setLikedVideos: (([String]) -> Int)?
    /// Video watching progress (Continue Watching, Recently Played), and taking in another Mac's.
    @ObservationIgnored var videoWatching: (() -> [ProfileSnapshot.VideoWatchState])?
    @ObservationIgnored var mergeVideoWatching: (([ProfileSnapshot.VideoWatchState]) -> Int)?
    @ObservationIgnored private var autoTimer: Timer?
    /// This Mac's data right after the last sync, to tell when something changed since.
    @ObservationIgnored private var syncedDigest: String?

    init(library: MusicLibrary) {
        self.library = library
        if isEnabled { start() }
    }

    /// The code saved for another Mac (entered the first time you synced with it).
    func savedCode(for peer: Peer) -> String? {
        (UserDefaults.standard.dictionary(forKey: "networkSyncPeerCodes") as? [String: String])?[peer.name]
    }

    private func saveCode(_ code: String, for peer: Peer) { saveCode(code, forName: peer.name) }

    private func saveCode(_ code: String, forName name: String) {
        var codes = UserDefaults.standard.dictionary(forKey: "networkSyncPeerCodes") as? [String: String] ?? [:]
        codes[name] = code
        UserDefaults.standard.set(codes, forKey: "networkSyncPeerCodes")
    }

    // MARK: - Announcing and finding Macs

    private func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: deviceName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in await self?.answer(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            lastMessage = "Couldn't start syncing on this network. \(error.localizedDescription)"
        }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found: [Peer] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return Peer(name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in
                guard let self else { return }
                let before = Set(self.peers.map(\.name))
                self.peers = found.filter { $0.name != self.deviceName }.sorted { $0.name < $1.name }
                // A Mac that just came online catches up with what changed while it was away.
                for peer in self.peers where !before.contains(peer.name) {
                    Task { await self.syncAutomatically(with: [peer]) }
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        autoTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncIfChanged() }
        }
    }

    private func stop() {
        autoTimer?.invalidate()
        autoTimer = nil
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        peers = []
    }

    // MARK: - Syncing

    /// This Mac's data plus the playlists deleted here, ready to send.
    private func mySnapshot() async throws -> ProfileSnapshot {
        var snapshot = try await library.database.profileSnapshot(deviceName: deviceName)
        snapshot.removedPlaylists = RemovedPlaylistsLog.recent
        snapshot.likedVideos = likedVideos?()
        snapshot.videoWatching = videoWatching?()
        return snapshot
    }

    /// The parts every kind of sync adds together (never removing anything): video progress and saved mixes.
    private func addTogether(_ snapshot: ProfileSnapshot, into report: inout ProfileMergeReport) async {
        if let watching = snapshot.videoWatching { report.videoProgressChanged = mergeVideoWatching?(watching) ?? 0 }
        if let mixes = snapshot.savedMixes {
            report.savedMixesAdded = (try? await library.database.mergeSavedMixes(mixes)) ?? 0
        }
    }

    /// Adds another Mac's data here (never bringing back playlists deleted here), then notes its deletions.
    private func combine(_ snapshot: ProfileSnapshot) async throws -> ProfileMergeReport {
        let skipping = Set(RemovedPlaylistsLog.recent.map(\.key))
        var report = try await library.database.mergeProfile(snapshot, skipping: skipping)
        if let theirs = snapshot.likedVideos {
            report.videoLikesChanged = setLikedVideos?(Array(Set(theirs).union(likedVideos?() ?? []))) ?? 0
        }
        await addTogether(snapshot, into: &report)
        await noteRemovals(in: snapshot)
        return report
    }

    /// Replaces this Mac's favorites, playlists and video likes with `snapshot`'s (backing up first).
    private func mirror(_ snapshot: ProfileSnapshot) async throws -> URL {
        let backup = try await backUpLibrary()
        _ = try await library.database.mirrorProfile(snapshot)
        if let theirs = snapshot.likedVideos { _ = setLikedVideos?(theirs) }
        var report = ProfileMergeReport()
        await addTogether(snapshot, into: &report)
        return backup
    }

    /// Makes this Mac match the agreed state of an automatic sync, and remembers how this Mac then looks.
    private func applyAgreed(_ agreed: ProfileSnapshot, mine: ProfileSnapshot, peer: String) async throws -> ProfileMergeReport {
        try await dailyBackup()
        var report = try await library.database.applyProfile(agreed, deleting: mine.playlistKeysMissing(from: agreed))
        if let videos = agreed.likedVideos { report.videoLikesChanged = setLikedVideos?(videos) ?? 0 }
        await addTogether(agreed, into: &report)
        SyncBase.save(try await mySnapshot(), peer: peer)
        return report
    }

    /// Deletions on the other Mac that match playlists here (and weren't answered "Keep" before).
    private func noteRemovals(in snapshot: ProfileSnapshot) async {
        let removed = (snapshot.removedPlaylists ?? []).filter { !RemovedPlaylistsLog.isIgnored($0) }
        guard !removed.isEmpty, let matches = try? await library.database.matchingPlaylists(for: removed), !matches.isEmpty
        else { return }
        pendingRemovalsFrom = snapshot.deviceName
        pendingRemovals = matches.map { (removed: $0.0, playlistId: $0.1) }
    }

    /// "Keep Them": don't ask about these deletions again.
    func keepPendingRemovals() {
        RemovedPlaylistsLog.ignore(pendingRemovals.map(\.removed))
        pendingRemovals = []
    }

    /// Sends this Mac's data to `peer`, gets theirs back, and adds it here (or replaces, per `mode`).
    func sync(with peer: Peer, code: String, mode: Mode = .combine) async {
        syncingWith = peer.name
        defer { syncingWith = nil }
        let connection = NWConnection(to: peer.endpoint, using: .tcp)
        defer { connection.cancel() }
        do {
            try await Wire.open(connection)
            let mine = try await mySnapshot()
            try await Wire.send(Request(code: code, snapshot: mine, mode: mode, senderCode: self.code,
                                        base: mode == .automatic ? SyncBase.load(peer: peer.name) : nil,
                                        profile: Profiles.active.name), on: connection)
            let response: Response = try await Wire.receive(on: connection)
            guard response.ok, let theirs = response.snapshot else {
                lastMessage = response.error ?? "\(peer.name) didn't accept the sync."
                return
            }
            saveCode(code, for: peer)
            switch mode {
            case .combine:
                let report = try await combine(theirs)
                lastMessage = "Combined with \(peer.name). Here: \(report.summary) There: \(response.report ?? "")"
            case .sendMine:
                lastMessage = "\(peer.name) now matches this Mac. \(response.report ?? "")"
            case .takeTheirs:
                let backup = try await mirror(theirs)
                lastMessage = "This Mac now matches \(peer.name). A copy of this Mac's library from before is in \(backup.lastPathComponent)."
            case .automatic:
                let report = try await applyAgreed(theirs, mine: mine, peer: peer.name)
                if report.changedSomething || response.report != nil {
                    lastMessage = "Synced with \(peer.name) automatically at \(Date().formatted(date: .omitted, time: .shortened)). "
                        + "Here: \(report.summary) There: \(response.report ?? "")"
                }
                await rememberSynced()
                if report.changedSomething { await onMerged?() }
                return
            }
            if mode != .automatic { SyncBase.save(try await mySnapshot(), peer: peer.name) }
            await rememberSynced()
            await onMerged?()
        } catch {
            lastMessage = "Couldn't sync with \(peer.name). \(error.localizedDescription)"
        }
    }

    // MARK: - Automatic sync

    /// Every 20 seconds: if anything changed here since the last sync, send it to the Macs synced with before.
    private func syncIfChanged() async {
        guard isEnabled, syncsAutomatically, syncingWith == nil,
              let digest = try? await Self.digest(mySnapshot()), digest != syncedDigest else { return }
        await syncAutomatically(with: peers)
    }

    /// Syncs with each of `peers` that this Mac has synced with before (it knows their code).
    func syncAutomatically(with peers: [Peer]) async {
        guard isEnabled, syncsAutomatically else { return }
        for peer in peers {
            guard syncingWith == nil, let code = savedCode(for: peer) else { continue }
            await sync(with: peer, code: code, mode: .automatic)
        }
    }

    /// An empty library (a new install, or the database not opened yet) would look like everything was deleted,
    /// so automatic sync stops and asks for a sync by hand instead.
    static func emptyLibraryProblem(_ a: ProfileSnapshot, _ b: ProfileSnapshot) -> String? {
        for snapshot in [a, b] where snapshot.songs.isEmpty && snapshot.playlists.isEmpty && snapshot.plays.isEmpty {
            return "Automatic sync paused: MacBee on “\(snapshot.deviceName)” has no favorites, playlists or plays yet. Use Sync Now and choose Combine."
        }
        return nil
    }

    private func rememberSynced() async {
        syncedDigest = try? await Self.digest(mySnapshot())
    }

    /// A summary of the data that syncs, independent of order, to notice changes.
    private static func digest(_ snapshot: ProfileSnapshot) throws -> String {
        var parts = snapshot.songs.map { "s\($0.key.fingerprint)|\($0.isFavorite)|\($0.rating ?? -1)" }.sorted()
        parts.append("plays \(snapshot.plays.count) \(snapshot.plays.map(\.playedAt).max()?.timeIntervalSince1970 ?? 0)")
        parts += snapshot.playlists.map { (["p"] + $0.folders + [$0.name, "\($0.capacitySeconds ?? 0)"] + $0.songs.map(\.fingerprint)).joined(separator: "|") }.sorted()
        parts += (snapshot.likedVideos ?? []).map { "v" + $0 }
        parts += (snapshot.videoWatching ?? []).map {
            "w\($0.key)|\(Int($0.position ?? -1))|\($0.lastWatched?.timeIntervalSince1970 ?? 0)|\($0.lastPlayed?.timeIntervalSince1970 ?? 0)|\($0.watched)"
        }
        parts += (snapshot.savedMixes ?? []).map { "m\($0.title)|\($0.createdAt.timeIntervalSince1970)" }
        return parts.joined(separator: "\n")
    }

    /// Automatic syncs change things without asking, so a copy of the library is kept from each day's first one.
    private func dailyBackup() async throws {
        let day = Date().formatted(.iso8601.year().month().day())
        guard UserDefaults.standard.string(forKey: "networkSyncBackupDay") != day else { return }
        let url = Profiles.directory.appendingPathComponent("Library-before-auto-sync.sqlite")
        try? FileManager.default.removeItem(at: url)
        try await library.database.backup(to: url)
        UserDefaults.standard.set(day, forKey: "networkSyncBackupDay")
    }

    /// Another Mac asked to sync: check its code, add its data here, send ours back.
    private func answer(_ connection: NWConnection) async {
        defer { connection.cancel() }
        do {
            try await Wire.open(connection)
            let request: Request = try await Wire.receive(on: connection)
            guard request.code == code else {
                try await Wire.send(Response(ok: false, error: "The code doesn't match. Check the code shown in MacBee > Settings > Sync on the other Mac."),
                                    on: connection)
                return
            }
            let from = request.snapshot.deviceName
            // Each person syncs with their own profile on the other Mac.
            let theirProfile = request.profile ?? Profiles.all.first { $0.id == Profiles.mainId }?.name ?? ""
            guard theirProfile.caseInsensitiveCompare(Profiles.active.name) == .orderedSame else {
                let problem = "\(from) is using the profile “\(theirProfile)” and this Mac “\(Profiles.active.name)”. Switch both Macs to the same profile to sync."
                try await Wire.send(Response(ok: false, error: problem), on: connection)
                if request.mode != .automatic { lastMessage = problem }
                return
            }
            // Remember the other Mac's code so this Mac can sync with it automatically too.
            if let senderCode = request.senderCode { saveCode(senderCode, forName: from) }
            switch request.mode ?? .combine {
            case .combine:
                let report = try await combine(request.snapshot)
                let mine = try await mySnapshot()
                try await Wire.send(Response(ok: true, snapshot: mine, report: report.summary), on: connection)
                lastMessage = "\(from) combined with this Mac. \(report.summary)"
            case .sendMine:
                // The other Mac asked for this one to match it.
                let backup = try await mirror(request.snapshot)
                let mine = try await mySnapshot()
                try await Wire.send(Response(ok: true, snapshot: mine, report: "Its playlists and favorites were replaced; a backup was saved there."),
                                    on: connection)
                lastMessage = "\(from) made this Mac match it. A copy of this Mac's library from before is in \(backup.lastPathComponent)."
            case .takeTheirs:
                // The other Mac will make itself match this one: just send ours.
                let mine = try await mySnapshot()
                try await Wire.send(Response(ok: true, snapshot: mine, report: nil), on: connection)
                lastMessage = "\(from) copied this Mac's playlists and favorites."
            case .automatic:
                let mine = try await mySnapshot()
                if let problem = Self.emptyLibraryProblem(mine, request.snapshot) {
                    try await Wire.send(Response(ok: false, error: problem), on: connection)
                    lastMessage = problem
                    return
                }
                let agreed = ProfileSnapshot.merged(mine: mine, myBase: SyncBase.load(peer: from),
                                                    theirs: request.snapshot, theirBase: request.base)
                let report = try await applyAgreed(agreed, mine: mine, peer: from)
                try await Wire.send(Response(ok: true, snapshot: agreed, report: report.changedSomething ? report.summary : nil),
                                    on: connection)
                await rememberSynced()
                if report.changedSomething {
                    lastMessage = "\(from) synced with this Mac automatically at \(Date().formatted(date: .omitted, time: .shortened)). \(report.summary)"
                    await onMerged?()
                }
                return
            }
            if request.mode != .automatic { SyncBase.save(try await mySnapshot(), peer: from) }
            await rememberSynced()
            await onMerged?()
        } catch {
            lastMessage = "A sync from another Mac didn't finish. \(error.localizedDescription)"
        }
    }

    /// Saves a copy of this Mac's library database before a sync replaces anything.
    private func backUpLibrary() async throws -> URL {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let url = Profiles.directory.appendingPathComponent("Library-before-sync-\(stamp).sqlite")
        try await library.database.backup(to: url)
        return url
    }

    struct Request: Codable {
        var code: String
        var snapshot: ProfileSnapshot
        /// Missing from older versions: combine.
        var mode: Mode?
        /// The sending Mac's own code, so the other Mac can start automatic syncs too. Missing from older versions.
        var senderCode: String?
        /// Automatic sync: how the sending Mac looked right after its last sync with this one.
        var base: ProfileSnapshot?
        /// The sending Mac's profile name; only the same person's data is synced. Missing from older versions
        /// (they only have the main profile).
        var profile: String?
    }

    struct Response: Codable {
        var ok: Bool
        var error: String?
        var snapshot: ProfileSnapshot?
        var report: String?
    }
}

/// How this Mac's data looked right after its last sync with each other Mac, so the next automatic sync can
/// tell what changed here since (including removals). Kept in Application Support > MacBee > Sync.
private enum SyncBase {
    static func url(peer: String) -> URL {
        let safe = peer.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return Profiles.directory.appendingPathComponent("Sync/\(String(safe)).json")
    }

    static func load(peer: String) -> ProfileSnapshot? {
        guard let data = try? Data(contentsOf: url(peer: peer)) else { return nil }
        return try? JSONDecoder().decode(ProfileSnapshot.self, from: data)
    }

    static func save(_ snapshot: ProfileSnapshot, peer: String) {
        let url = url(peer: peer)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}

/// Lets a callback that may run several times resume a continuation only once. (All on the main queue.)
private final class Once: @unchecked Sendable {
    private var done = false
    func claim() -> Bool {
        if done { return false }
        done = true
        return true
    }
}

/// Length-prefixed JSON messages over a TCP connection.
private enum Wire {
    enum Failure: LocalizedError {
        case closed, tooBig
        var errorDescription: String? {
            switch self {
            case .closed: "The connection closed."
            case .tooBig: "The message was too big."
            }
        }
    }

    static func open(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume() }
                case let .failed(error), let .waiting(error):
                    if once.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if once.claim() { continuation.resume(throwing: Failure.closed) }
                default: break
                }
            }
            connection.start(queue: .main)
        }
    }

    static func send<T: Encodable>(_ value: T, on connection: NWConnection) async throws {
        let body = try JSONEncoder().encode(value)
        var length = UInt32(body.count).bigEndian
        let frame = Data(bytes: &length, count: 4) + body
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    static func receive<T: Decodable>(on connection: NWConnection) async throws -> T {
        let header = try await read(4, from: connection)
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        guard length < 200_000_000 else { throw Failure.tooBig }
        let body = try await read(length, from: connection)
        return try JSONDecoder().decode(T.self, from: body)
    }

    private static func read(_ count: Int, from connection: NWConnection) async throws -> Data {
        var data = Data()
        while data.count < count {
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: count - data.count) { content, _, isComplete, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let content, !content.isEmpty { continuation.resume(returning: content) }
                    else if isComplete { continuation.resume(throwing: Failure.closed) }
                    else { continuation.resume(returning: Data()) }
                }
            }
            data.append(chunk)
        }
        return data
    }
}
