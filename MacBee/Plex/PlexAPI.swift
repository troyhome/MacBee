import AppKit
import Foundation

/// Talks to plex.tv (sign-in, account, servers) and to a Plex Media Server (music libraries, files).
struct PlexAPI {
    enum Failure: LocalizedError {
        case http(Int)
        case notSignedIn
        var errorDescription: String? {
            switch self {
            case let .http(code): "Plex replied with error \(code)."
            case .notSignedIn: "You're not signed in to Plex."
            }
        }
    }

    static let product = "MacBee"

    /// Identifies this Mac's copy of MacBee to Plex (kept the same between launches).
    static var clientIdentifier: String {
        let key = "plexClientIdentifier"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    let session: URLSession

    init(timeout: TimeInterval = 20) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        session = URLSession(configuration: config)
    }

    // MARK: - plex.tv

    func createPin() async throws -> PlexPin {
        try await decode(PlexPin.self, from: request("https://plex.tv/api/v2/pins", method: "POST",
                                                      query: ["strong": "true"]))
    }

    func checkPin(_ pin: PlexPin) async throws -> PlexPin {
        try await decode(PlexPin.self, from: request("https://plex.tv/api/v2/pins/\(pin.id)", query: ["code": pin.code]))
    }

    /// The page where the user approves MacBee (opened in their browser).
    static func approvalURL(for pin: PlexPin) -> URL {
        let id = clientIdentifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientIdentifier
        return URL(string: "https://app.plex.tv/auth#?clientID=\(id)&code=\(pin.code)&context%5Bdevice%5D%5Bproduct%5D=\(product)")!
    }

    func user(token: String) async throws -> PlexUser {
        try await decode(PlexUser.self, from: request("https://plex.tv/api/v2/user", token: token))
    }

    func servers(token: String) async throws -> [PlexServer] {
        try await decode([PlexServer].self, from: request("https://plex.tv/api/v2/resources", token: token,
                                                          query: ["includeHttps": "1", "includeRelay": "1"]))
            .filter(\.isServer)
    }

    // MARK: - Plex Media Server

    /// True when the server answers at this address (quick check, a few seconds at most).
    func isReachable(_ base: URL, token: String) async -> Bool {
        var req = request(base.appendingPathComponent("identity").absoluteString, token: token)
        req.timeoutInterval = 4
        guard let (_, response) = try? await session.data(for: req) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func musicSections(base: URL, token: String) async throws -> [PlexSection] {
        let reply = try await decode(PlexSectionsReply.self,
                                     from: request(base.appendingPathComponent("library/sections").absoluteString, token: token))
        return (reply.container.directories ?? []).filter { $0.type == "artist" }
    }

    /// Every song file in a music library: (path on the server, part key used to download it).
    func allTrackFiles(base: URL, token: String, sectionKey: String) async throws -> [(path: String, partKey: String)] {
        var files: [(String, String)] = []
        var start = 0
        let pageSize = 1000
        while true {
            let url = base.appendingPathComponent("library/sections/\(sectionKey)/all").absoluteString
            let reply = try await decode(PlexTracksReply.self, from: request(url, token: token, query: [
                "type": "10", "X-Plex-Container-Start": "\(start)", "X-Plex-Container-Size": "\(pageSize)",
            ]))
            let page = reply.container.tracks ?? []
            for track in page {
                for part in track.media?.flatMap({ $0.parts ?? [] }) ?? [] {
                    if let file = part.file { files.append((file, part.key)) }
                }
            }
            start += page.count
            if page.isEmpty || start >= (reply.container.totalSize ?? start) { break }
        }
        return files
    }

    /// Downloads the original file (no conversion), so playback stays bit-perfect.
    func download(partKey: String, base: URL, token: String, to destination: URL) async throws {
        var components = URLComponents(url: base.appendingPathComponent(partKey), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "download", value: "1")]
        var req = request(components.url!.absoluteString, token: token)
        req.timeoutInterval = 120
        let (temp, response) = try await session.download(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    // MARK: - Helpers

    private func request(_ url: String, method: String = "GET", token: String? = nil,
                         query: [String: String] = [:]) -> URLRequest {
        var components = URLComponents(string: url)!
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.product, forHTTPHeaderField: "X-Plex-Product")
        req.setValue(Self.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                     forHTTPHeaderField: "X-Plex-Version")
        req.setValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
        req.setValue(Host.current().localizedName ?? "Mac", forHTTPHeaderField: "X-Plex-Device-Name")
        if let token { req.setValue(token, forHTTPHeaderField: "X-Plex-Token") }
        return req
    }

    private func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
