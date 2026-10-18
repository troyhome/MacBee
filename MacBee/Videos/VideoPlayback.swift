import Foundation
import MacBeeVideo

/// What the video player is showing: one file, plus what to play when it ends (the next episodes).
struct VideoPlayback: Identifiable, Equatable {
    var title: String
    /// e.g. "Scrubs · S1 · E3", or the year for a movie.
    var subtitle: String
    var file: VideoFile
    /// The id used for likes (movie file path, show folder or music video path).
    var likeId: String
    /// Episodes to continue with, in order.
    var upNext: [(title: String, subtitle: String, file: VideoFile)] = []

    var id: String { file.path }

    static func == (lhs: VideoPlayback, rhs: VideoPlayback) -> Bool { lhs.file == rhs.file }
}
