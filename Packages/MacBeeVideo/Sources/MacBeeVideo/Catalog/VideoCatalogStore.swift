import Foundation

/// Saves the catalog between launches, so the Videos page opens instantly instead of re-reading a big drive.
public enum VideoCatalogStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee/videos.json")
    }

    public static func load(from url: URL = defaultURL) -> VideoCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VideoCatalog.self, from: data)
    }

    public static func save(_ catalog: VideoCatalog, to url: URL = defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(catalog) { try? data.write(to: url, options: .atomic) }
    }
}
