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
        case .leadIn, .recording: true
        default: false
        }
    }

    /// 1-based number of the song now playing, while recording.
    var currentNumber: Int? {
        guard phase == .recording, let index = player.queue.currentIndex else { return nil }
        return index + 1
    }

    func start() {
        guard !tracks.isEmpty, !isRunning else { return }
        savedShuffle = player.queue.isShuffled
        savedRepeat = player.queue.repeatMode
        player.queue.setShuffled(false)
        player.queue.repeatMode = .off
        player.engine.stop()
        player.engine.setRecordOut(RecordOutMode(gap: gap))
        player.queueFinishedOverride = { [weak self] in self?.finish() }

        leadInTask = Task { [weak self] in
            for left in stride(from: Self.leadInSeconds, to: 0, by: -1) {
                self?.phase = .leadIn(secondsLeft: left)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            phase = .recording
            player.play(tracks)
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

    private func finish() {
        cleanUp()
        phase = .finished
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
