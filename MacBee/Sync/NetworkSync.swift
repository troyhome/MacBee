import Foundation
import MacBeeLibrary
@preconcurrency import Network
import Observation

/// Keeps two MacBees on the same network in step (roadmap Phase 5): play counts and history, favorites,
/// ratings and playlists. Each Mac with "Sync with my other Macs" on announces itself on the local network
/// (Bonjour) and shows a 6-digit code; the other Mac enters that code once, then "Sync Now" swaps everything
/// both ways. Nothing is ever deleted by a sync. Music files are not copied: both Macs need the same music.
@MainActor
@Observable
final class NetworkSync {
    struct Peer: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    static let serviceType = "_macbee-sync._tcp"

    private(set) var peers: [Peer] = []
    private(set) var syncingWith: String?
    /// The result of the last sync (either direction).
    private(set) var lastMessage: String?

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

    @ObservationIgnored private let library: MusicLibrary
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var browser: NWBrowser?
    /// Called after another Mac's data was added here (to refresh playlists and lists).
    @ObservationIgnored var onMerged: (() async -> Void)?

    init(library: MusicLibrary) {
        self.library = library
        if isEnabled { start() }
    }

    /// The code saved for another Mac (entered the first time you synced with it).
    func savedCode(for peer: Peer) -> String? {
        (UserDefaults.standard.dictionary(forKey: "networkSyncPeerCodes") as? [String: String])?[peer.name]
    }

    private func saveCode(_ code: String, for peer: Peer) {
        var codes = UserDefaults.standard.dictionary(forKey: "networkSyncPeerCodes") as? [String: String] ?? [:]
        codes[peer.name] = code
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
                self.peers = found.filter { $0.name != self.deviceName }.sorted { $0.name < $1.name }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        peers = []
    }

    // MARK: - Syncing

    /// Sends this Mac's data to `peer`, gets theirs back, and adds it here.
    func sync(with peer: Peer, code: String) async {
        syncingWith = peer.name
        defer { syncingWith = nil }
        let connection = NWConnection(to: peer.endpoint, using: .tcp)
        defer { connection.cancel() }
        do {
            try await Wire.open(connection)
            let mine = try await library.database.profileSnapshot(deviceName: deviceName)
            try await Wire.send(Request(code: code, snapshot: mine), on: connection)
            let response: Response = try await Wire.receive(on: connection)
            guard response.ok, let theirs = response.snapshot else {
                lastMessage = response.error ?? "\(peer.name) didn't accept the sync."
                return
            }
            saveCode(code, for: peer)
            let report = try await library.database.mergeProfile(theirs)
            await onMerged?()
            lastMessage = "Synced with \(peer.name). Here: \(report.summary) There: \(response.report ?? "")"
        } catch {
            lastMessage = "Couldn't sync with \(peer.name). \(error.localizedDescription)"
        }
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
            let report = try await library.database.mergeProfile(request.snapshot)
            let mine = try await library.database.profileSnapshot(deviceName: deviceName)
            try await Wire.send(Response(ok: true, snapshot: mine, report: report.summary), on: connection)
            await onMerged?()
            lastMessage = "\(request.snapshot.deviceName) synced with this Mac. \(report.summary)"
        } catch {
            lastMessage = "A sync from another Mac didn't finish. \(error.localizedDescription)"
        }
    }

    struct Request: Codable {
        var code: String
        var snapshot: ProfileSnapshot
    }

    struct Response: Codable {
        var ok: Bool
        var error: String?
        var snapshot: ProfileSnapshot?
        var report: String?
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
