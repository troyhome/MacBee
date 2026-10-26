import Foundation
import GRDB

/// A playlist or a playlist folder. Stored in the `playlist` table.
/// Folders hold playlists and other folders (`parentFolderId`); `sortOrder` orders siblings.
public struct Playlist: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public var parentFolderId: Int64?
    public var isFolder: Bool
    public var sortOrder: Int
    public var createdAt: Date
    /// A picture chosen for the playlist (nil shows a collage of its album covers).
    public var artworkId: Int64?
    /// A running-time limit in seconds (MiniDisc mixes: 60, 74 or 80 minutes). Nil for ordinary playlists.
    public var capacitySeconds: Int? = nil

    public static let databaseTableName = "playlist"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// One song in a playlist. Stored in the `playlistItem` table.
struct PlaylistItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var playlistId: Int64
    var trackId: Int64
    var position: Int

    static let databaseTableName = "playlistItem"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A song as it appears in a playlist: the entry's own id (the same song can be in a playlist twice) and the track.
public struct PlaylistEntry: Identifiable, Hashable, Sendable {
    public var itemId: Int64
    public var track: Track
    public var id: Int64 { itemId }
}

/// Song count, length and covers for a playlist's header or card.
public struct PlaylistSummary: Hashable, Sendable {
    public var trackCount: Int
    public var duration: Double
    /// Up to four different covers for a collage.
    public var artworkIds: [Int64]

    public init(trackCount: Int = 0, duration: Double = 0, artworkIds: [Int64] = []) {
        self.trackCount = trackCount
        self.duration = duration
        self.artworkIds = artworkIds
    }

    public static let empty = PlaylistSummary()
}

/// A playlist folder with what's inside it, for the sidebar.
public struct PlaylistNode: Identifiable, Hashable, Sendable {
    public var playlist: Playlist
    public var children: [PlaylistNode]
    public var id: Int64 { playlist.id ?? -1 }
}

public enum PlaylistTree {
    /// Nests playlists under their folders, each level sorted by `sortOrder` then name.
    /// Anything whose folder is missing is shown at the top level.
    public static func build(_ playlists: [Playlist]) -> [PlaylistNode] {
        let ids = Set(playlists.compactMap(\.id))
        let byParent = Dictionary(grouping: playlists) { p -> Int64? in
            guard let parent = p.parentFolderId, ids.contains(parent) else { return nil }
            return parent
        }
        func nodes(under parent: Int64?) -> [PlaylistNode] {
            (byParent[parent] ?? [])
                .sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
                .map { PlaylistNode(playlist: $0, children: $0.isFolder ? nodes(under: $0.id) : []) }
        }
        return nodes(under: nil)
    }
}
