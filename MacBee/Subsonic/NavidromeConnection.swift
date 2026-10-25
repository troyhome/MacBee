import Foundation
import MacBeeLibrary
import Observation

/// MacBee's Navidrome (or other Subsonic server) connection: sign-in, matching the server's songs to the library,
/// and fetching original files when the network drive can't be reached. Works like the Plex connection.
@MainActor
@Observable
final class NavidromeConnection {
    private(set) var serverAddress: String = UserDefaults.standard.string(forKey: "navidromeAddress") ?? ""
    private(set) var username: String = UserDefaults.standard.string(forKey: "navidromeUsername") ?? ""
    private(set) var isConnected = false
    private(set) var isMatching = false
    private(set) var linkedCount = 0
    /// Shown in Settings after connecting or matching, or when something goes wrong.
    var message: String?

    /// Track id -> server song id.
    @ObservationIgnored private(set) var links: [Int64: String] = [:]
    @ObservationIgnored private let library: MusicLibrary
    @ObservationIgnored private var api: SubsonicAPI?

    private static let passwordAccount = "navidrome"

    private static var linksURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee/Navidrome-Links.json")
    }

    var isSetUp: Bool { api != nil }

    init(library: MusicLibrary) {
        self.library = library
        if let data = try? Data(contentsOf: Self.linksURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            links = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in Int64(key).map { ($0, value) } })
            linkedCount = links.count
        }
        if let url = URL(string: serverAddress), !username.isEmpty,
           let password = KeychainStore.read(account: Self.passwordAccount) {
            api = SubsonicAPI(baseURL: url, username: username, password: password)
            Task { await check() }
        }
    }

    // MARK: - Sign in / out

    /// Saves the server and sign-in after checking them, then matches the library.
    func connect(address: String, username: String, password: String) async {
        var address = address.trimmingCharacters(in: .whitespaces)
        if !address.contains("://") { address = "http://" + address }
        guard let url = URL(string: address) else {
            message = SubsonicAPI.Failure.badAddress.localizedDescription
            return
        }
        let candidate = SubsonicAPI(baseURL: url, username: username, password: password)
        do {
            try await candidate.ping()
        } catch {
            message = "Couldn't connect. \(error.localizedDescription)"
            return
        }
        KeychainStore.save(password, account: Self.passwordAccount)
        UserDefaults.standard.set(address, forKey: "navidromeAddress")
        UserDefaults.standard.set(username, forKey: "navidromeUsername")
        serverAddress = address
        self.username = username
        api = candidate
        isConnected = true
        message = nil
        await matchLibrary()
    }

    func disconnect() {
        KeychainStore.delete(account: Self.passwordAccount)
        UserDefaults.standard.removeObject(forKey: "navidromeAddress")
        UserDefaults.standard.removeObject(forKey: "navidromeUsername")
        api = nil
        isConnected = false
        serverAddress = ""
        username = ""
        links = [:]
        linkedCount = 0
        try? FileManager.default.removeItem(at: Self.linksURL)
        message = nil
    }

    /// Checks the server can be reached right now.
    @discardableResult
    func check() async -> Bool {
        guard let api else { return false }
        isConnected = (try? await api.ping()) != nil
        return isConnected
    }

    // MARK: - Matching

    /// Pairs the server's songs with the library's.
    func matchLibrary() async {
        guard let api, !isMatching else { return }
        isMatching = true
        defer { isMatching = false }
        do {
            let remote = try await api.allSongs()
            let local = try await library.database.localSongsForSubsonicMatching()
            let matched = await Task.detached { SubsonicMatcher.match(remote: remote, local: local) }.value
            links = matched
            linkedCount = matched.count
            let saved = Dictionary(uniqueKeysWithValues: matched.map { (String($0.key), $0.value) })
            try? JSONEncoder().encode(saved).write(to: Self.linksURL, options: .atomic)
            message = "Matched \(matched.count.formatted()) of your \(local.count.formatted()) songs with the server."
        } catch {
            message = "Couldn't match songs with the server. \(error.localizedDescription)"
        }
    }

    // MARK: - Files

    /// Downloads a song's original file into `destination`.
    func download(trackId: Int64, to destination: URL) async throws {
        guard let api, let songId = links[trackId] else { throw SubsonicAPI.Failure.server("This song isn't on the server.") }
        try await api.download(songId: songId, to: destination)
    }
}
