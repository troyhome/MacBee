import Foundation

/// Looks up a song's lyrics online at LRCLIB (lrclib.net, free and open, no account), preferring lyrics with
/// timings so they follow the music. Matched by artist, title, album and length.
public enum LyricsFinder {
    public struct Found: Equatable, Sendable {
        /// Ready to save as an .lrc file: LRC lines with times, or plain text.
        public var text: String
        public var isTimed: Bool
    }

    public enum Outcome: Equatable, Sendable {
        case found(Found)
        /// LRCLIB knows the song and says it has no words.
        case instrumental
        case notFound
    }

    static let agent = "MacBee (https://github.com/troyhome/MacBee)"

    public static func find(artist: String, title: String, album: String, duration: Double,
                            session: URLSession = .shared) async throws -> Outcome {
        // Exact lookup first (LRCLIB allows a couple of seconds' difference in length).
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [.init(name: "artist_name", value: artist), .init(name: "track_name", value: title),
                          .init(name: "album_name", value: album), .init(name: "duration", value: String(Int(duration.rounded())))]
        if let record = try await fetch(single: true, from: get.url!, session: session)?.first,
           let outcome = outcome(of: record) {
            return outcome
        }
        // Then a search, keeping only results about as long as the song (so a live or edited version isn't used).
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [.init(name: "artist_name", value: artist), .init(name: "track_name", value: title)]
        let results = try await fetch(single: false, from: search.url!, session: session) ?? []
        let close = results.filter { abs(($0.duration ?? 0) - duration) <= 3 }
        let best = close.first { $0.syncedLyrics?.isEmpty == false } ?? close.first { $0.plainLyrics?.isEmpty == false }
            ?? close.first { $0.instrumental == true }
        return best.flatMap(outcome(of:)) ?? .notFound
    }

    struct Record: Decodable {
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    static func outcome(of record: Record) -> Outcome? {
        if let synced = record.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !synced.isEmpty {
            return .found(Found(text: synced, isTimed: true))
        }
        if let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return .found(Found(text: plain, isTimed: false))
        }
        return record.instrumental == true ? .instrumental : nil
    }

    /// `single`: the endpoint returns one record (404 when there's none) rather than a list.
    private static func fetch(single: Bool, from url: URL, session: URLSession) async throws -> [Record]? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return single ? [try JSONDecoder().decode(Record.self, from: data)] : try JSONDecoder().decode([Record].self, from: data)
    }
}
