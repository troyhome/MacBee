import AppKit
import Foundation

/// One cover found online for an album.
struct CoverCandidate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let source: String        // "Apple Music" or "MusicBrainz"
    let album: String
    let artist: String
    let year: String
    let thumbnail: Data
    let fullURL: URL
}

/// Looks up album covers on Apple Music (iTunes Search) and MusicBrainz's Cover Art Archive.
/// Both are free and need no account. MusicBrainz asks for at most one request a second, so callers
/// search one album at a time.
enum CoverFinder {
    private static let userAgent = "MacBee/1.0 ( https://github.com/troyhome/MacBee )"

    static func search(artist: String, album: String) async -> [CoverCandidate] {
        let term = [artist, album].filter { !$0.isEmpty }.joined(separator: " ")
        guard !term.isEmpty else { return [] }
        async let apple = appleMusic(term, artist: artist, album: album)
        async let brainz = musicBrainz(artist: artist, album: album)
        return await apple + brainz
    }

    /// The full-size cover, as JPEG or PNG data ready to embed.
    static func download(_ candidate: CoverCandidate) async -> Data? {
        guard let data = await get(candidate.fullURL, timeout: 30) else { return nil }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) || data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return data }
        // Anything else (WebP, GIF...) becomes a JPEG so every player can show it.
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    // MARK: - Sources

    private static func appleMusic(_ term: String, artist: String, album: String) async -> [CoverCandidate] {
        func albums(_ term: String, limit: Int) async -> [[String: Any]] {
            var url = URLComponents(string: "https://itunes.apple.com/search")!
            url.queryItems = [.init(name: "term", value: term), .init(name: "entity", value: "album"),
                              .init(name: "limit", value: "\(limit)")]
            guard let data = await get(url.url!),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            return json["results"] as? [[String: Any]] ?? []
        }
        var results = await albums(term, limit: 8)
        if results.isEmpty, !artist.isEmpty {
            // Apple's search sometimes misses "artist album" together; try the artist's albums and match the title.
            let want = norm(album)
            results = await albums(artist, limit: 200).filter {
                let name = norm($0["collectionName"] as? String ?? "")
                return !want.isEmpty && (name == want || name.hasPrefix(want))
            }
        }
        var found: [CoverCandidate] = []
        for r in results.prefix(8) {
            guard let art = r["artworkUrl100"] as? String,
                  let thumbURL = URL(string: art.replacingOccurrences(of: "100x100bb", with: "300x300bb")),
                  let fullURL = URL(string: art.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")),
                  let thumb = await get(thumbURL) else { continue }
            found.append(CoverCandidate(source: "Apple Music", album: r["collectionName"] as? String ?? "",
                                        artist: r["artistName"] as? String ?? "",
                                        year: String((r["releaseDate"] as? String ?? "").prefix(4)),
                                        thumbnail: thumb, fullURL: fullURL))
        }
        return found
    }

    private static func musicBrainz(artist: String, album: String) async -> [CoverCandidate] {
        var query = "releasegroup:\"\(album.replacingOccurrences(of: "\"", with: ""))\""
        if !artist.isEmpty { query += " AND artist:\"\(artist.replacingOccurrences(of: "\"", with: ""))\"" }
        var url = URLComponents(string: "https://musicbrainz.org/ws/2/release-group/")!
        url.queryItems = [.init(name: "query", value: query), .init(name: "fmt", value: "json"),
                          .init(name: "limit", value: "5")]
        guard let data = await get(url.url!),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = json["release-groups"] as? [[String: Any]] else { return [] }
        var found: [CoverCandidate] = []
        for g in groups {
            guard let id = g["id"] as? String,
                  let thumbURL = URL(string: "https://coverartarchive.org/release-group/\(id)/front-250"),
                  let fullURL = URL(string: "https://coverartarchive.org/release-group/\(id)/front-1200"),
                  let thumb = await get(thumbURL) else { continue }   // many have no cover; skip those
            let credits = g["artist-credit"] as? [[String: Any]] ?? []
            let name = credits.map { ($0["name"] as? String ?? "") + ($0["joinphrase"] as? String ?? "") }.joined()
            found.append(CoverCandidate(source: "MusicBrainz", album: g["title"] as? String ?? "", artist: name,
                                        year: String((g["first-release-date"] as? String ?? "").prefix(4)),
                                        thumbnail: thumb, fullURL: fullURL))
        }
        return found
    }

    /// Lowercase letters and digits only, for comparing album titles.
    static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    private static func get(_ url: URL, timeout: TimeInterval = 15) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for attempt in 0..<3 {
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return data.isEmpty ? nil : data }
            // 503 = MusicBrainz asking us to slow down; wait and try again.
            guard status == 503 || status == 429, attempt < 2 else { return nil }
            try? await Task.sleep(for: .milliseconds(1500 * (attempt + 1)))
        }
        return nil
    }
}
