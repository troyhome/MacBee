import Foundation

/// Plex movie and TV libraries: used for posters, genres and descriptions on the Videos page.
extension PlexAPI {
    func videoSections(base: URL, token: String) async throws -> [PlexSection] {
        let reply = try await decode(PlexSectionsReply.self,
                                     from: request(base.appendingPathComponent("library/sections").absoluteString, token: token))
        return (reply.container.directories ?? []).filter { $0.type == "movie" || $0.type == "show" }
    }

    /// Every item of one kind in a library (Plex types: 1 movie, 2 show, 4 episode), a page at a time.
    func allVideoItems(base: URL, token: String, sectionKey: String, type: Int) async throws -> [PlexVideoReply.Item] {
        var items: [PlexVideoReply.Item] = []
        let pageSize = 500
        while true {
            let url = base.appendingPathComponent("library/sections/\(sectionKey)/all").absoluteString
            let reply = try await decode(PlexVideoReply.self, from: request(url, token: token, query: [
                "type": "\(type)", "X-Plex-Container-Start": "\(items.count)", "X-Plex-Container-Size": "\(pageSize)",
            ]))
            let page = reply.container.items ?? []
            items += page
            if page.isEmpty || items.count >= (reply.container.totalSize ?? items.count) { break }
        }
        return items
    }

    /// Downloads a poster, resized by Plex to at most 600 × 900.
    func downloadPoster(_ thumb: String, base: URL, token: String, to destination: URL) async throws {
        let url = base.appendingPathComponent("photo/:/transcode").absoluteString
        let req = request(url, token: token, query: ["width": "600", "height": "900", "minSize": "1", "url": thumb])
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
}
