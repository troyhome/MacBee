import AppKit
import Foundation
import MacBeeLibrary
import Observation

/// MacBee's Plex connection: sign-in, choosing the server and music library, matching Plex's songs to the
/// library, and downloading original files when the network drive can't be reached.
@MainActor
@Observable
final class PlexConnection: PlexService {
    enum Status: Equatable {
        case signedOut
        /// The browser is open; waiting for the user to approve MacBee on plex.tv.
        case waitingForApproval
        case signedIn
    }

    /// How the server is being reached right now.
    enum Route: Equatable {
        case unknown, homeNetwork, internet, relay, unreachable
        var title: String {
            switch self {
            case .unknown: "Not checked yet"
            case .homeNetwork: "Connected on your home network"
            case .internet: "Connected over the internet"
            case .relay: "Connected through Plex Relay (slower)"
            case .unreachable: "Can't reach the server"
            }
        }
    }

    private(set) var status: Status = .signedOut
    private(set) var username: String?
    private(set) var servers: [PlexServer] = []
    private(set) var sections: [PlexSection] = []
    private(set) var route: Route = .unknown
    private(set) var linkedCount = 0
    private(set) var isMatching = false
    /// Shown in Preferences after matching or when something goes wrong.
    var message: String?

    var selectedServerId: String? {
        didSet {
            UserDefaults.standard.set(selectedServerId, forKey: "plexServerId")
            if oldValue != selectedServerId { Task { await serverChanged() } }
        }
    }
    var selectedSectionKey: String? {
        didSet { UserDefaults.standard.set(selectedSectionKey, forKey: "plexSectionKey") }
    }

    var isSignedIn: Bool { status == .signedIn }
    var selectedServer: PlexServer? { servers.first { $0.id == selectedServerId } }

    @ObservationIgnored private let api = PlexAPI()
    @ObservationIgnored private let library: MusicLibrary
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var baseURL: URL?
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    /// Track id -> part key, for quick lookups while playing.
    @ObservationIgnored private(set) var links: [Int64: String] = [:]

    init(library: MusicLibrary) {
        self.library = library
        selectedServerId = UserDefaults.standard.string(forKey: "plexServerId")
        selectedSectionKey = UserDefaults.standard.string(forKey: "plexSectionKey")
        if let saved = KeychainStore.read(account: KeychainStore.plexTokenAccount) {
            token = saved
            status = .signedIn
            Task { await loadAccount() }
        }
    }

    // MARK: - Sign in / out (PlexService)

    /// Opens plex.tv in the browser; when the user approves MacBee there, the sign-in completes by itself.
    func signIn() async throws {
        let pin = try await api.createPin()
        status = .waitingForApproval
        message = nil
        NSWorkspace.shared.open(PlexAPI.approvalURL(for: pin))
        signInTask?.cancel()
        signInTask = Task {
            // Check every 2 seconds for up to 10 minutes.
            for _ in 0..<300 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                if let checked = try? await api.checkPin(pin), let authToken = checked.authToken {
                    KeychainStore.save(authToken, account: KeychainStore.plexTokenAccount)
                    token = authToken
                    status = .signedIn
                    await loadAccount()
                    return
                }
            }
            status = .signedOut
            message = "The sign-in wasn't approved in time. Click Sign In to try again."
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        status = .signedOut
    }

    func signOut() {
        signInTask?.cancel()
        KeychainStore.delete(account: KeychainStore.plexTokenAccount)
        token = nil
        baseURL = nil
        status = .signedOut
        username = nil
        servers = []
        sections = []
        route = .unknown
        links = [:]
        linkedCount = 0
        Task { try? await library.database.replacePlexLinks([:]) }
    }

    // MARK: - Account, server, library

    private func loadAccount() async {
        guard let token else { return }
        do {
            let user = try await api.user(token: token)
            username = user.username ?? user.title
        } catch PlexAPI.Failure.http(401) {
            message = "Your Plex sign-in has expired. Please sign in again."
            signOut()
            return
        } catch {
            message = "Couldn't reach plex.tv. \(error.localizedDescription)"
        }
        do {
            servers = try await api.servers(token: token)
            if selectedServer == nil {
                selectedServerId = (servers.first { $0.owned == true } ?? servers.first)?.id
            } else {
                await serverChanged()
            }
        } catch {
            message = "Couldn't get your Plex servers. \(error.localizedDescription)"
        }
        links = (try? await library.database.plexLinksDictionary()) ?? [:]
        linkedCount = links.count
    }

    private func serverChanged() async {
        baseURL = nil
        route = .unknown
        guard await connect() != nil, let base = baseURL, let server = selectedServer else { return }
        do {
            sections = try await api.musicSections(base: base, token: serverToken(server))
            if !sections.contains(where: { $0.key == selectedSectionKey }) { selectedSectionKey = sections.first?.key }
            if links.isEmpty, (try? await library.database.plexLinkCount()) == 0 { await matchLibrary() }
        } catch {
            message = "Couldn't read the server's libraries. \(error.localizedDescription)"
        }
    }

    /// Finds a working address: home network first, then the internet, then Plex Relay.
    @discardableResult
    func connect() async -> URL? {
        guard let server = selectedServer else { return nil }
        let token = serverToken(server)
        let ordered = server.connections.filter { $0.local && !$0.relay }
            + server.connections.filter { !$0.local && !$0.relay }
            + server.connections.filter(\.relay)
        for address in ordered {
            guard let url = URL(string: address.uri) else { continue }
            if await api.isReachable(url, token: token) {
                baseURL = url
                route = address.relay ? .relay : (address.local ? .homeNetwork : .internet)
                return url
            }
        }
        baseURL = nil
        route = .unreachable
        return nil
    }

    // MARK: - Matching songs

    /// Pairs every song in the Plex music library with the same file in MacBee's library.
    func matchLibrary() async {
        guard !isMatching, let server = selectedServer, let section = selectedSectionKey else { return }
        isMatching = true
        defer { isMatching = false }
        do {
            guard let base = await currentBase() else {
                message = "Can't reach your Plex server right now."
                return
            }
            let plexFiles = try await api.allTrackFiles(base: base, token: serverToken(server), sectionKey: section)
                .map { PlexMatcher.PlexFile(path: $0.path, partKey: $0.partKey) }
            let localFiles = try await library.database.localFilesForMatching()
            let matched = await Task.detached { PlexMatcher.match(plexFiles: plexFiles, localFiles: localFiles) }.value
            try await library.database.replacePlexLinks(matched)
            links = matched
            linkedCount = matched.count
            message = "Matched \(matched.count.formatted()) of your \(localFiles.count.formatted()) songs with Plex."
        } catch {
            message = "Couldn't match songs with Plex. \(error.localizedDescription)"
        }
    }

    // MARK: - Files

    /// Downloads a song's original file from Plex into `destination`.
    func download(trackId: Int64, to destination: URL) async throws {
        guard let partKey = links[trackId], let server = selectedServer else { throw PlexAPI.Failure.notSignedIn }
        guard let base = await currentBase() else { throw PlexAPI.Failure.http(-1) }
        do {
            try await api.download(partKey: partKey, base: base, token: serverToken(server), to: destination)
        } catch {
            // The network may have changed (e.g. left home): find a new address and try once more.
            guard let fresh = await connect() else { throw error }
            try await api.download(partKey: partKey, base: fresh, token: serverToken(server), to: destination)
        }
    }

    /// The server address and token, for the Videos page's Plex lookups.
    func serverAccess() async -> (URL, String)? {
        guard let server = selectedServer, let base = await currentBase() else { return nil }
        return (base, serverToken(server))
    }

    /// The working server address, finding one if needed.
    private func currentBase() async -> URL? {
        if let baseURL { return baseURL }
        return await connect()
    }

    private func serverToken(_ server: PlexServer) -> String {
        server.accessToken ?? token ?? ""
    }
}
