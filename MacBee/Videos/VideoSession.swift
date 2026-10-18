import Foundation
import MacBeeVideo
import Observation

/// One video being watched: the mpv player, what's playing, and what comes next. Shared by the full-window
/// player and the mini player window, so switching between them doesn't interrupt playback.
/// Saves where you are every 10 seconds and when it stops; plays the next episode when one ends.
@MainActor
@Observable
final class VideoSession {
    let player = MPVPlayer()
    private(set) var current: VideoPlayback

    @ObservationIgnored private let library: VideoLibrary
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    init(playback: VideoPlayback, library: VideoLibrary) {
        current = playback
        self.library = library
        player.load(playback.file.url, startAt: library.position(of: playback.file.path))
        watchTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                ticks += 1
                if ticks % 10 == 0 { self.savePosition() }
                if self.player.reachedEnd { self.playNext() }
            }
        }
    }

    /// Saves the position and shuts the player down.
    func stop() {
        watchTask?.cancel()
        savePosition()
        player.shutdown()
    }

    private func savePosition() {
        guard player.duration > 0 else { return }
        library.savePosition(player.position, duration: player.duration, for: current.file.path)
    }

    private func playNext() {
        library.savePosition(player.duration, duration: player.duration, for: current.file.path)
        // Continuous Play (Videos > TV Shows, or Settings > General) off: stop after this episode.
        guard UserDefaults.standard.object(forKey: "continuousPlayEpisodes") as? Bool ?? true else { return }
        guard let next = current.upNext.first else { return }
        var item = VideoPlayback(title: next.title, subtitle: next.subtitle, file: next.file, likeId: current.likeId)
        item.upNext = Array(current.upNext.dropFirst())
        current = item
        player.load(item.file.url, startAt: 0)
    }
}
