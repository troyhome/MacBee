import Foundation
import MacBeeAudio
import MacBeeLibrary
import Observation

/// Plays a list of songs into a recorder that has no USB (any MiniDisc, cassette, ...): a short lead-in,
/// then each song with a silent gap so the recorder starts a new track number for it. The output is kept at
/// 48 kHz or lower (MiniDisc records at 44.1 kHz). Shuffle and repeat are turned off while it runs and
/// put back afterwards.
@MainActor
@Observable
final class RecordOutSession {
    enum Phase: Equatable {
        case setup
        case leadIn(secondsLeft: Int)
        case recording
        /// Stopped at the end of a song by "Pause After This Song"; Resume Play continues with the next one.
        case paused
        case finished
        case stopped
    }

    let tracks: [Track]
    private(set) var phase: Phase = .setup
    /// Seconds of silence between songs.
    var gap: Double {
        didSet { UserDefaults.standard.set(gap, forKey: "recordOutGap") }
    }
    /// Disc length in minutes (60, 74 or 80).
    var discMinutes: Int

    static let leadInSeconds = 3
    static let discLengths = [60, 74, 80]

    /// "Pause After This Song" was clicked: the list stops when the current song ends.
    private(set) var pauseAfterCurrent = false
    /// Index (into `tracks`) of the first song in the current run; Resume Play starts a new run.
    private(set) var runStart = 0
    /// Index of the song Resume Play starts with.
    private var resumeIndex = 0

    @ObservationIgnored private let player: PlayerViewModel
    @ObservationIgnored private var leadInTask: Task<Void, Never>?
    @ObservationIgnored private var savedShuffle = false
    @ObservationIgnored private var savedRepeat = RepeatMode.off

    init(tracks: [Track], player: PlayerViewModel, discMinutes: Int? = nil) {
        self.tracks = tracks
        self.player = player
        let saved = UserDefaults.standard.double(forKey: "recordOutGap")
        gap = saved > 0 ? saved : 3
        self.discMinutes = discMinutes.flatMap { Self.discLengths.contains($0) ? $0 : nil } ?? 74
    }

    /// Recording time: all songs plus the gaps between them.
    var totalSeconds: Double {
        tracks.map(\.duration).reduce(0, +) + gap * Double(max(tracks.count - 1, 0))
    }

    var isRunning: Bool {
        switch phase {
        case .leadIn, .recording, .paused: true
        default: false
        }
    }

    /// 1-based number of the song now playing, while recording.
    var currentNumber: Int? {
        switch phase {
        case .recording:
            guard let index = player.queue.currentIndex else { return nil }
            return runStart + index + 1
        case .paused:
            return resumeIndex // the last song played
        default:
            return nil
        }
    }

    func start() {
        guard !tracks.isEmpty, !isRunning else { return }
        runStart = 0
        pauseAfterCurrent = false
        savedShuffle = player.queue.isShuffled
        savedRepeat = player.queue.repeatMode
        player.queue.setShuffled(false)
        player.queue.repeatMode = .off
        player.engine.stop()
        player.engine.setRecordOut(RecordOutMode(gap: gap))
        player.queueFinishedOverride = { [weak self] in self?.listEnded() }
        playAfterLeadIn(from: 0)
    }

    /// Lets the current song finish, then stops (the songs after it are kept for Resume Play).
    /// Clicking again before the song ends cancels it.
    func togglePauseAfterCurrent() {
        guard phase == .recording, let number = currentNumber else { return }
        if pauseAfterCurrent {
            pauseAfterCurrent = false
            player.addToQueue(Array(tracks[number...]))
        } else {
            pauseAfterCurrent = true
            resumeIndex = number
            player.clearUpNext()
        }
    }

    /// Continues with the song after the last one played, after the same lead-in as Start.
    func resume() {
        guard phase == .paused, tracks.indices.contains(resumeIndex) else { return }
        pauseAfterCurrent = false
        playAfterLeadIn(from: resumeIndex)
    }

    private func playAfterLeadIn(from index: Int) {
        leadInTask = Task { [weak self] in
            for left in stride(from: Self.leadInSeconds, to: 0, by: -1) {
                self?.phase = .leadIn(secondsLeft: left)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            runStart = index
            phase = .recording
            player.play(Array(tracks[index...]))
        }
    }

    func stop() {
        guard isRunning else { return }
        player.engine.stop()
        cleanUp()
        phase = .stopped
    }

    /// Puts things back when the window closes in any state.
    func close() {
        if isRunning { stop() } else { cleanUp() }
    }

    /// "1. Title – Artist" per song, for typing titles on the recorder.
    var trackNames: String {
        tracks.enumerated()
            .map { "\($0.offset + 1). \($0.element.displayTitle) – \($0.element.displayArtist)" }
            .joined(separator: "\n")
    }

    private func listEnded() {
        if pauseAfterCurrent && tracks.indices.contains(resumeIndex) {
            pauseAfterCurrent = false
            phase = .paused
        } else {
            cleanUp()
            phase = .finished
        }
    }

    private func cleanUp() {
        leadInTask?.cancel()
        leadInTask = nil
        guard player.engine.recordOut != nil || player.queueFinishedOverride != nil else { return }
        player.engine.setRecordOut(nil)
        player.queueFinishedOverride = nil
        player.queue.setShuffled(savedShuffle)
        player.queue.repeatMode = savedRepeat
    }
}
