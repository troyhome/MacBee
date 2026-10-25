import CryptoKit
import Foundation
import MacBeeLibrary

/// The Subsonic API, spoken by Navidrome, Gonic, Airsonic, Ampache and others.
/// Each request signs in with the username and a salted token made from the password (the password itself is
/// never sent).
struct SubsonicAPI: Sendable {
    let baseURL: URL
    let username: String
    let password: String

    enum Failure: LocalizedError {
        case http(Int)
        case server(String)
        case badAddress

        var errorDescription: String? {
            switch self {
            case let .http(code): "The server answered with error \(code)."
            case let .server(message): message
            case .badAddress: "That server address doesn't look right. It should start with http:// or https://."
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    /// Checks the address and sign-in.
    func ping() async throws {
        _ = try await call("ping")
    }

    /// Every song on the server, a page at a time (an empty search lists everything on Navidrome).
    func allSongs() async throws -> [SubsonicMatcher.RemoteSong] {
        var songs: [SubsonicMatcher.RemoteSong] = []
        let page = 500
        var offset = 0
        while true {
            let json = try await call("search3", query: ["query": "", "songCount": "\(page)", "songOffset": "\(offset)",
                                                         "artistCount": "0", "albumCount": "0"])
            let found = ((json["searchResult3"] as? [String: Any])?["song"] as? [[String: Any]]) ?? []
            songs += found.compactMap { song in
                guard let id = song["id"] as? String else { return nil }
                return SubsonicMatcher.RemoteSong(id: id, path: song["path"] as? String, artist: song["artist"] as? String,
                                                  title: song["title"] as? String, album: song["album"] as? String,
                                                  duration: (song["duration"] as? NSNumber)?.doubleValue)
            }
            if found.count < page { return songs }
            offset += page
        }
    }

    /// Downloads a song's original file (not converted) into `destination`.
    func download(songId: String, to destination: URL) async throws {
        var request = URLRequest(url: try url("download", query: ["id": songId]))
        request.timeoutInterval = 120
        let (temp, response) = try await Self.session.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        // A Subsonic error comes back as a small JSON or XML answer instead of the file.
        if (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json") || (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("xml") {
            throw Failure.server("The server didn't send the song file.")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    // MARK: - Requests

    private func call(_ method: String, query: [String: String] = [:]) async throws -> [String: Any] {
        let (data, response) = try await Self.session.data(from: try url(method, query: query))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let root = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["subsonic-response"] as? [String: Any]
        else { throw Failure.server("The server's answer wasn't understood. Is this a Subsonic or Navidrome server?") }
        if root["status"] as? String != "ok" {
            let message = (root["error"] as? [String: Any])?["message"] as? String
            throw Failure.server(message ?? "The server said no.")
        }
        return root
    }

    private func url(_ method: String, query: [String: String]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/\(method).view"),
                                             resolvingAgainstBaseURL: false),
              components.scheme == "http" || components.scheme == "https" else { throw Failure.badAddress }
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        let auth = ["u": username, "t": token, "s": String(salt), "v": "1.16.1", "c": "MacBee", "f": "json"]
        components.queryItems = auth.merging(query) { _, new in new }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw Failure.badAddress }
        return url
    }
}
