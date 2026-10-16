import Foundation

// Shapes of Plex's JSON replies (only the fields MacBee uses).

struct PlexPin: Decodable {
    let id: Int
    let code: String
    let authToken: String?
}

struct PlexUser: Decodable {
    let username: String?
    let title: String?
}

/// A Plex server on the account, with the addresses it can be reached at.
struct PlexServer: Decodable, Identifiable, Hashable {
    let name: String
    let clientIdentifier: String
    let provides: String
    let accessToken: String?
    let owned: Bool?
    let connections: [PlexAddress]

    var id: String { clientIdentifier }
    var isServer: Bool { provides.split(separator: ",").contains("server") }
}

struct PlexAddress: Decodable, Hashable {
    let uri: String
    let local: Bool
    let relay: Bool
}

struct PlexSection: Decodable, Identifiable, Hashable {
    let key: String
    let type: String
    let title: String
    var id: String { key }
}

struct PlexSectionsReply: Decodable {
    struct Container: Decodable {
        let directories: [PlexSection]?
        enum CodingKeys: String, CodingKey { case directories = "Directory" }
    }
    let container: Container
    enum CodingKeys: String, CodingKey { case container = "MediaContainer" }
}

struct PlexTracksReply: Decodable {
    struct Container: Decodable {
        let totalSize: Int?
        let size: Int?
        let tracks: [Track]?
        enum CodingKeys: String, CodingKey { case totalSize, size, tracks = "Metadata" }
    }
    struct Track: Decodable {
        let media: [Media]?
        enum CodingKeys: String, CodingKey { case media = "Media" }
    }
    struct Media: Decodable {
        let parts: [Part]?
        enum CodingKeys: String, CodingKey { case parts = "Part" }
    }
    struct Part: Decodable {
        let key: String
        let file: String?
    }
    let container: Container
    enum CodingKeys: String, CodingKey { case container = "MediaContainer" }
}
