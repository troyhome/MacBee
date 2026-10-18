import Foundation

/// Supplies the next track so the engine can pre-load it for gapless playback.
/// The app's QueueManager (Phase 5) adopts this.
@MainActor
public protocol PlaybackQueueSource: AnyObject {
    /// The track that should play after `url`, or `nil` at the end of the queue.
    func track(after url: URL) -> URL?
    /// The engine moved to `url` on its own (end of previous track).
    func engineDidAdvance(to url: URL)
}

/// What the UI and app services talk to. Keeping this as a protocol lets us
/// swap in a mock for UI previews/tests, or a streaming engine for Plex later.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var state: PlaybackState { get }
    var currentTrack: URL? { get }
    var currentFormat: AudioFormatInfo? { get }
    var progress: PlaybackProgress { get }
    var signalPath: SignalPathStatus? { get }
    var outputDevice: AudioDevice? { get }
    /// The output device's current sample rate (Hz), for the Now Playing format line.
    var deviceSampleRate: Double { get }
    /// The output device's current bit depth, if known.
    var deviceBitDepth: Int? { get }
    var settings: OutputSettings { get }
    var queueSource: PlaybackQueueSource? { get set }
    var lastError: String? { get }

    /// The 16-band EQ. Off by default; when off or flat it is taken out of the signal path entirely.
    var equalizer: EqualizerSettings { get }
    func applyEqualizer(_ settings: EqualizerSettings)

    /// Applies new output settings. Restarts the current track only when required (device or DSD mode change).
    func apply(_ settings: OutputSettings)

    /// Starts `url` immediately, replacing whatever is playing.
    func play(_ url: URL) async throws
    func pause()
    func resume()
    func togglePlayPause()
    func stop()
    func seek(to seconds: TimeInterval)

    /// Call after the queue changes (reorder, shuffle, removal) so the pre-loaded next track is refreshed.
    func queueDidChange()

    /// 0...1. Routes to the DAC or to software gain depending on `settings.volumeMode`.
    var volume: Float { get }
    /// False when the DAC has no volume control; volume is then fixed at 100% in hardware mode.
    var hardwareVolumeAvailable: Bool { get }
    func setVolume(_ volume: Float)

    func availableOutputDevices() -> [AudioDevice]
    /// Stops playback and gives up exclusive access. Call on app quit.
    func shutdown()
}
