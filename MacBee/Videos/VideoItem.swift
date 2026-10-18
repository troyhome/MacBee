import Foundation

/// A music video file found in one of the music folders.
struct VideoItem: Identifiable, Hashable, Sendable {
    let url: URL
    /// The file name without its extension, e.g. "Balthazar - Losers".
    let title: String
    /// The folder it's in, shown under the title.
    let folderName: String
    let modified: Date

    var id: URL { url }

    /// File types macOS can play without extra software.
    static let extensions: Set<String> = ["mp4", "m4v", "mov"]
}
