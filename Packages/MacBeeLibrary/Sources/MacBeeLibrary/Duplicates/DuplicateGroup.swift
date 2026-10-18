import Foundation

/// One song with several copies, for the Duplicates page. The first copy is the one the library shows.
public struct DuplicateGroup: Identifiable, Sendable, Hashable {
    public struct Copy: Sendable, Hashable, Identifiable {
        public var track: Track
        public var folderName: String
        public var id: String { track.path }
    }

    public var id: Int64
    public var copies: [Copy]

    public init(id: Int64, copies: [Copy]) {
        self.id = id
        self.copies = copies
    }

    public var shown: Track { copies[0].track }
    public var extras: [Copy] { Array(copies.dropFirst()) }
}
