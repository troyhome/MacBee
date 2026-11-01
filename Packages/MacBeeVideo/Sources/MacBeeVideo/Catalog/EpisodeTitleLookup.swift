import Foundation

/// Episode names from TVmaze (free, no account) for shows whose files carry no names and that Plex doesn't
/// cover. Results are kept on this Mac, so each show is looked up once (and again after a week if some
/// episodes were still missing, e.g. a season that hadn't aired).
public actor EpisodeTitleLookup {
    struct Saved: Codable {
        /// "S1E1" -> "Pilot"
        var titles: [String: String]
        var fetchedAt: Date
    }

    private let fileURL: URL
    private var saved: [String: Saved]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        saved = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:]
    }

    /// Fills in missing episode names. Shows whose episodes all have names are left alone (no network).
    public func fillMissingTitles(in catalog: VideoCatalog) async -> VideoCatalog {
        var catalog = catalog
        var changed = false
        for i in catalog.shows.indices {
            let show = catalog.shows[i]
            let missing = show.seasons.flatMap(\.episodes).filter { $0.title == nil }
            guard !missing.isEmpty else { continue }
            let key = Self.key(show)
            var entry = saved[key]
            let stale = entry.map { Date().timeIntervalSince($0.fetchedAt) > 7 * 24 * 3600 } ?? true
            let covers = entry.map { e in missing.allSatisfy { e.titles[Self.code($0)] != nil } } ?? false
            if entry == nil || (!covers && stale) {
                if let titles = await Self.fetch(title: show.title, year: show.year) {
                    entry = Saved(titles: titles, fetchedAt: Date())
                    saved[key] = entry
                    changed = true
                }
            }
            guard let titles = entry?.titles else { continue }
            for s in catalog.shows[i].seasons.indices {
                for e in catalog.shows[i].seasons[s].episodes.indices where catalog.shows[i].seasons[s].episodes[e].title == nil {
                    catalog.shows[i].seasons[s].episodes[e].title = titles[Self.code(catalog.shows[i].seasons[s].episodes[e])]
                }
            }
        }
        if changed, let data = try? JSONEncoder().encode(saved) { try? data.write(to: fileURL, options: .atomic) }
        return catalog
    }

    static func key(_ show: Show) -> String { "\(show.title.lowercased())|\(show.year.map(String.init) ?? "")" }
    static func code(_ episode: Episode) -> String { "S\(episode.season)E\(episode.number)" }

    /// The show's episode names from TVmaze, choosing the show that started in `year` when there are several.
    static func fetch(title: String, year: Int?) async -> [String: String]? {
        var search = URLComponents(string: "https://api.tvmaze.com/search/shows")!
        search.queryItems = [URLQueryItem(name: "q", value: title)]
        guard let url = search.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let shows = results.compactMap { $0["show"] as? [String: Any] }
        let chosen = shows.first { show in
            guard let year, let premiered = show["premiered"] as? String else { return false }
            return premiered.hasPrefix(String(year))
        } ?? shows.first
        guard let id = chosen?["id"] as? Int,
              let episodesURL = URL(string: "https://api.tvmaze.com/shows/\(id)/episodes"),
              let (episodeData, _) = try? await URLSession.shared.data(from: episodesURL),
              let episodes = try? JSONSerialization.jsonObject(with: episodeData) as? [[String: Any]] else { return nil }
        var titles: [String: String] = [:]
        for episode in episodes {
            guard let season = episode["season"] as? Int, let number = episode["number"] as? Int,
                  let name = episode["name"] as? String, !name.isEmpty else { continue }
            titles["S\(season)E\(number)"] = name
        }
        return titles.isEmpty ? nil : titles
    }
}
