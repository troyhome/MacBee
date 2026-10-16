import Foundation

/// What's being dragged inside MacBee, sent as plain text (e.g. "macbee:tracks:12,13").
enum DragPayload: Equatable {
    case tracks([Int64])
    case album(String)
    case artist(String)
    case playlist(Int64)

    private static let prefix = "macbee:"

    var string: String {
        switch self {
        case let .tracks(ids): Self.prefix + "tracks:" + ids.map(String.init).joined(separator: ",")
        case let .album(key): Self.prefix + "album:" + key
        case let .artist(key): Self.prefix + "artist:" + key
        case let .playlist(id): Self.prefix + "playlist:\(id)"
        }
    }

    init?(string: String) {
        guard string.hasPrefix(Self.prefix) else { return nil }
        let parts = string.dropFirst(Self.prefix.count).split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "tracks": self = .tracks(parts[1].split(separator: ",").compactMap { Int64($0) })
        case "album": self = .album(parts[1])
        case "artist": self = .artist(parts[1])
        case "playlist":
            guard let id = Int64(parts[1]) else { return nil }
            self = .playlist(id)
        default: return nil
        }
    }

    /// True for songs, albums and artists (things that can be added to a playlist).
    var carriesSongs: Bool {
        if case .playlist = self { return false }
        return true
    }
}
