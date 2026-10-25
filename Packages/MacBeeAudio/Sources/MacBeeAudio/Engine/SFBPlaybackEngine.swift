import AVFoundation
import Foundation
import Observation
import SFBAudioEngine

/// Bit-perfect playback built on SFBAudioEngine.
///
/// How bit-perfect is kept:
/// - Before each track, the DAC is switched to the track's sample rate, so nothing is resampled.
/// - The DAC is set to its highest integer bit depth, so nothing is truncated.
/// - Volume stays at unity in software unless the user chooses software volume.
/// - Optional exclusive (hog) mode keeps other apps from mixing in.
///
/// Gapless: the next track is pre-loaded when the current one starts decoding.
/// If it has the same format it plays with no gap. If the sample rate differs,
/// the DAC must switch, so the engine waits for the current track to end, switches, then starts it.
@MainActor
@Observable
public final class SFBPlaybackEngine: PlaybackEngine {

    // MARK: Observable state

    public private(set) var state: PlaybackState = .stopped
    public private(set) var currentTrack: URL?
    public private(set) var currentFormat: AudioFormatInfo?
    public private(set) var progress = PlaybackProgress()
    public private(set) var signalPath: SignalPathStatus?
    public private(set) var outputDevice: AudioDevice?
    public private(set) var deviceSampleRate: Double = 0
    public private(set) var deviceBitDepth: Int?
    public private(set) var volume: Float = 1
    public private(set) var lastError: String?
    public private(set) var settings: OutputSettings
    public private(set) var equalizer: EqualizerSettings = .off
    public private(set) var recordOut: RecordOutMode?

    public var hardwareVolumeAvailable: Bool { outputDevice?.hasHardwareVolume ?? false }

    @ObservationIgnored public weak var queueSource: PlaybackQueueSource?
    /// Optional callback stream (logging, CLI, analytics).
    @ObservationIgnored public var eventHandler: (@MainActor (PlaybackEngineEvent) -> Void)?

    // MARK: Internals

    @ObservationIgnored private let player = AudioPlayer()
    @ObservationIgnored private let devices = AudioDeviceManager()
    @ObservationIgnored private let delegateProxy = PlayerDelegateProxy()
    @ObservationIgnored private let equalizerNode = EqualizerNode()
    @ObservationIgnored private var decoderFactory: DecoderFactory

    /// Next track already handed to the player for gapless playback.
    @ObservationIgnored private var enqueuedNext: URL?
    /// Next track with a different format; started after the current one ends.
    @ObservationIgnored private var pendingNext: (url: URL, decoder: PCMDecoding)?
    @ObservationIgnored private var lastDecodingURL: URL?
    @ObservationIgnored private var formats: [URL: AudioFormatInfo] = [:]
    /// Set when the user picks a track, so we don't report it as an automatic advance.
    @ObservationIgnored private var userRequestedURL: URL?
    /// Guards against overlapping `play` calls (e.g. rapid skipping).
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    /// True while a video plays: exclusive mode is let go so the video's sound can reach the device.
    @ObservationIgnored private var exclusiveModeOnBreak = false
    /// A device that wouldn't start in exclusive mode; it plays shared until the output settings change.
    @ObservationIgnored private var exclusiveModeBlockedDeviceID: AudioObjectID?
    @ObservationIgnored private var isStarting = false
    /// Next track currently loading into memory in the background.
    @ObservationIgnored private var preloadingURL: URL?
    @ObservationIgnored private var preloadTask: Task<Void, Never>?
    /// The current track ended before the next one finished loading; start it as soon as it's ready.
    @ObservationIgnored private var startWhenPreloaded = false
    /// Recording mode: a song ended and the next one starts after the silent gap.
    @ObservationIgnored private var waitingInGap = false

    public init(settings: OutputSettings = .default) {
        self.settings = settings
        self.decoderFactory = DecoderFactory(dsdMode: settings.dsdMode, loadIntoMemory: settings.loadIntoMemory)
        delegateProxy.engine = self
        delegateProxy.equalizer = equalizerNode
        player.delegate = delegateProxy
        devices.onDevicesChanged = { [weak self] in self?.devicesChanged() }
        outputDevice = devices.resolveDevice(uid: settings.deviceUID)
        if let device = outputDevice {
            deviceSampleRate = devices.nominalSampleRate(of: device.id)
            deviceBitDepth = devices.currentBitDepth(of: device.id)
        }
        applyVolume()
    }

    // MARK: - Transport

    public func play(_ url: URL) async throws {
        generation += 1
        let myGeneration = generation
        lastError = nil
        stopPlayer()
        // Loads the whole file in the background (network-safe), then plays.
        let decoder = try await decoderFactory.loadDecoder(for: url)
        guard myGeneration == generation else { return } // a newer play() won
        try await start(decoder, url: url, userInitiated: true, generation: myGeneration)
    }

    public func pause() {
        player.pause()
    }

    public func setRecordOut(_ mode: RecordOutMode?) {
        guard mode != recordOut else { return }
        recordOut = mode
        // Re-plan the next song: gapless while listening, separate (with a gap) while recording.
        if state != .stopped { queueDidChange() }
    }

    public func resume() {
        player.resume()
    }

    public func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        case .stopped:
            guard let url = currentTrack else { return }
            Task { do { try await play(url) } catch { report(error) } }
        }
    }

    public func stop() {
        generation += 1
        stopPlayer()
        state = .stopped
        progress = PlaybackProgress(elapsed: 0, duration: progress.duration)
        releaseExclusiveAccess()
        emit(.stateChanged(.stopped))
    }

    public func seek(to seconds: TimeInterval) {
        guard player.supportsSeeking else { return }
        player.seek(time: max(0, seconds))
        refreshProgress()
    }

    public func queueDidChange() {
        // In a recording gap the next song is already scheduled; re-plan it from the changed queue.
        let wasInGap = waitingInGap
        if wasInGap {
            waitingInGap = false
            generation += 1
        }
        cancelPreload()
        if enqueuedNext != nil || pendingNext != nil {
            player.clearQueue()
            enqueuedNext = nil
            pendingNext = nil
        }
        if let url = lastDecodingURL ?? currentTrack {
            preloadNext(after: url)
        }
        if wasInGap {
            if preloadingURL != nil { startWhenPreloaded = true } else { finishQueue() }
        }
    }

    public func shutdown() {
        stop()
        progressTask?.cancel()
    }

    // MARK: - Settings, devices, volume

    public func availableOutputDevices() -> [AudioDevice] {
        devices.outputDevices()
    }

    public func apply(_ newSettings: OutputSettings) {
        let old = settings
        settings = newSettings
        if old.deviceUID != newSettings.deviceUID || old.exclusiveMode != newSettings.exclusiveMode {
            exclusiveModeBlockedDeviceID = nil
        }
        decoderFactory.dsdMode = newSettings.dsdMode
        decoderFactory.loadIntoMemory = newSettings.loadIntoMemory

        let needsRestart = old.deviceUID != newSettings.deviceUID
            || (old.dsdMode != newSettings.dsdMode && currentFormat?.isDSD == true)
            || old.preferHighestBitDepth != newSettings.preferHighestBitDepth

        if needsRestart && state != .stopped {
            restartCurrentTrack()
            return
        }
        if old.deviceUID != newSettings.deviceUID {
            switchIdleDevice()
        }
        if old.exclusiveMode != newSettings.exclusiveMode {
            if newSettings.exclusiveMode, state != .stopped { acquireExclusiveAccess() } else { releaseExclusiveAccess() }
        }
        applyVolume()
        updateSignalPath()
    }

    public func applyEqualizer(_ newValue: EqualizerSettings) {
        let wasActive = equalizer.isActive
        equalizer = newValue
        equalizerNode.update(newValue, player: player)
        if wasActive != newValue.isActive { updateSignalPath() }
    }

    public func setVolume(_ newValue: Float) {
        let v = min(max(newValue, 0), 1)
        switch settings.volumeMode {
        case .hardware:
            guard let device = outputDevice, device.hasHardwareVolume else { return }
            do { try devices.setHardwareVolume(v, on: device.id); volume = v } catch { report(error) }
        case .software:
            settings.softwareVolume = v
            _ = try? player.setVolume(v)
            volume = v
            updateSignalPath()
        }
    }

    // MARK: - Starting a track

    private func start(_ decoder: PCMDecoding, url: URL, userInitiated: Bool, generation myGeneration: Int) async throws {
        isStarting = true
        defer { isStarting = false }
        let info = DecoderFactory.formatInfo(for: decoder, url: url)
        formats[url] = info

        try await prepareOutput(for: info)
        // A newer play() call arrived while we waited for the DAC; let it win.
        guard myGeneration == generation else { return }

        userRequestedURL = userInitiated ? url : nil
        do {
            try player.play(decoder)
        } catch where outputDevice.map({ devices.ownsHogMode($0.id) }) == true {
            // Exclusive mode can keep the device from starting, e.g. when Boom 3D's driver also sends its
            // sound there. Play shared rather than not at all; the decoder is already queued.
            exclusiveModeBlockedDeviceID = outputDevice?.id
            releaseExclusiveAccess()
            report(AudioEngineError.exclusiveModeBlocked(outputDevice?.name ?? "the output device"))
            try player.play()
        }
        startProgressUpdates()
    }

    /// Picks the device, exclusive mode, sample rate and bit depth for a track.
    private func prepareOutput(for info: AudioFormatInfo) async throws {
        guard let device = devices.resolveDevice(uid: settings.deviceUID) else {
            throw AudioEngineError.noOutputDevice
        }
        if let old = outputDevice, old.id != device.id {
            devices.releaseHogMode(on: old.id)
        }
        if player.outputDeviceID != device.id {
            try player.setOutputDeviceID(device.id)
        }
        outputDevice = device

        if settings.exclusiveMode { acquireExclusiveAccess() } else { releaseExclusiveAccess() }

        // Virtual devices (Boom 3D etc.) are left exactly as they are; changing them can cause loud noise.
        if !device.isVirtual {
            let supported = recordOut?.allowedRates(device.supportedSampleRates) ?? device.supportedSampleRates
            let target = SampleRatePolicy.bestRate(for: info.deliveredSampleRate,
                                                   supported: supported) ?? info.deliveredSampleRate
            do {
                try await devices.setNominalSampleRate(target, on: device.id)
            } catch {
                report(error) // Keep playing; the signal path will show the resampling.
            }
        }
        deviceSampleRate = devices.nominalSampleRate(of: device.id)

        if settings.preferHighestBitDepth && !device.isVirtual {
            deviceBitDepth = (try? devices.selectHighestBitDepth(on: device.id, sampleRate: deviceSampleRate))
                ?? devices.currentBitDepth(of: device.id)
        } else {
            deviceBitDepth = devices.currentBitDepth(of: device.id)
        }

        applyVolume()
        emit(.outputChanged(deviceName: device.name, sampleRate: deviceSampleRate, bitDepth: deviceBitDepth))
    }

    private func stopPlayer() {
        player.stop()
        player.clearQueue()
        enqueuedNext = nil
        pendingNext = nil
        lastDecodingURL = nil
        userRequestedURL = nil
        waitingInGap = false
        cancelPreload()
    }

    private func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
        preloadingURL = nil
        startWhenPreloaded = false
    }

    // MARK: - Gapless lookahead

    /// Loads the next track into memory in the background while the current one plays.
    private func preloadNext(after url: URL) {
        guard let next = queueSource?.track(after: url) else { return }
        if enqueuedNext == next || pendingNext?.url == next || preloadingURL == next { return }
        cancelPreload()
        preloadingURL = next
        let myGeneration = generation
        let factory = decoderFactory
        preloadTask = Task {
            do {
                let decoder = try await factory.loadDecoder(for: next)
                // Skip if the user changed tracks or the queue while we were loading.
                guard !Task.isCancelled, myGeneration == generation, preloadingURL == next else { return }
                preloadingURL = nil
                formats[next] = DecoderFactory.formatInfo(for: decoder, url: next)

                if startWhenPreloaded {
                    // Current track already ended; start right away.
                    startWhenPreloaded = false
                    startNext(url: next, decoder: decoder)
                } else if recordOut == nil && player.formatWillBeGaplessIfEnqueued(decoder.processingFormat) {
                    try player.enqueue(decoder)
                    enqueuedNext = next
                } else {
                    pendingNext = (next, decoder)
                }
            } catch {
                guard preloadingURL == next else { return }
                preloadingURL = nil
                report(error)
                if startWhenPreloaded { startWhenPreloaded = false; finishQueue() }
            }
        }
    }

    private func restartCurrentTrack() {
        guard let url = currentTrack else { return }
        let time = player.currentTime ?? 0
        let wasPaused = state == .paused
        Task {
            do {
                try await play(url)
                if time > 1 { seek(to: time) }
                if wasPaused { pause() }
            } catch {
                report(error)
            }
        }
    }

    private func switchIdleDevice() {
        let resolved = devices.resolveDevice(uid: settings.deviceUID)
        if let old = outputDevice, old.id != resolved?.id { devices.releaseHogMode(on: old.id) }
        outputDevice = resolved
        if let id = resolved?.id {
            try? player.setOutputDeviceID(id)
            deviceSampleRate = devices.nominalSampleRate(of: id)
            deviceBitDepth = devices.currentBitDepth(of: id)
        }
    }

    // MARK: - Player callbacks (main actor, via PlayerDelegateProxy)

    func handleDecodingStarted(_ url: URL?) {
        guard let url else { return }
        lastDecodingURL = url
        preloadNext(after: url)
    }

    func handleNowPlayingChanged(_ url: URL?) {
        guard let url else { return } // End of queue is handled in handleEndOfAudio.
        if url == enqueuedNext { enqueuedNext = nil }
        let automatic = url != userRequestedURL
        userRequestedURL = nil

        currentTrack = url
        currentFormat = formats[url]
        formats = formats.filter { $0.key == url || $0.key == enqueuedNext || $0.key == pendingNext?.url }
        updateSignalPath(announce: false)
        if let format = currentFormat { emit(.trackStarted(url, format)) }
        if automatic { queueSource?.engineDidAdvance(to: url) }
    }

    func handlePlaybackStateChanged() {
        let newState: PlaybackState
        switch player.playbackState {
        case .playing: newState = .playing
        case .paused: newState = .paused
        default: newState = .stopped
        }
        guard newState != state else { return }
        state = newState
        emit(.stateChanged(newState))
    }

    func handleEndOfAudio() {
        // Ignore stale notifications from a track we just replaced.
        if pendingNext == nil && (isStarting || player.currentDecoder != nil) { return }
        if let pending = pendingNext {
            // Different sample rate (or recording): switch the DAC, then continue, after a silent gap
            // when recording.
            pendingNext = nil
            startNext(url: pending.url, decoder: pending.decoder, after: recordOut?.gap ?? 0)
        } else if preloadingURL != nil {
            // Next track is still loading (slow network). Start it when it arrives.
            startWhenPreloaded = true
        } else {
            finishQueue()
        }
    }

    private func startNext(url: URL, decoder: PCMDecoding, after delay: TimeInterval = 0) {
        generation += 1
        let myGeneration = generation
        player.stop()
        Task {
            if delay > 0 {
                waitingInGap = true
                try? await Task.sleep(for: .seconds(delay))
                guard myGeneration == generation else { return } // stopped, queue changed or another song chosen
                waitingInGap = false
            }
            do {
                try await start(decoder, url: url, userInitiated: false, generation: myGeneration)
            } catch {
                report(error)
            }
        }
    }

    private func finishQueue() {
        state = .stopped
        progressTask?.cancel()
        releaseExclusiveAccess()
        emit(.stateChanged(.stopped))
        emit(.queueFinished)
    }

    func handleOutputConfigurationChanged() {
        // Something (us, or another app / Audio MIDI Setup) changed the device. Re-read and re-check.
        guard let device = outputDevice else { return }
        deviceSampleRate = devices.nominalSampleRate(of: device.id)
        deviceBitDepth = devices.currentBitDepth(of: device.id)
        applyVolume()
        updateSignalPath()
    }

    func report(_ message: String) {
        lastError = message
        emit(.error(message))
    }

    func report(_ error: Error) {
        report(error.localizedDescription)
    }

    // MARK: - Helpers

    private func devicesChanged() {
        let resolved = devices.resolveDevice(uid: settings.deviceUID)
        guard resolved?.id != outputDevice?.id else { return }
        if state == .stopped { switchIdleDevice(); applyVolume() } else { restartCurrentTrack() }
    }

    /// Lets another player in this app (the video player) use the device while exclusive mode is on.
    /// Exclusive mode comes back with `endExclusiveModeBreak()`.
    public func startExclusiveModeBreak() {
        exclusiveModeOnBreak = true
        releaseExclusiveAccess()
    }

    public func endExclusiveModeBreak() {
        guard exclusiveModeOnBreak else { return }
        exclusiveModeOnBreak = false
        if settings.exclusiveMode, state != .stopped { acquireExclusiveAccess() }
    }

    private func acquireExclusiveAccess() {
        guard !exclusiveModeOnBreak, let device = outputDevice, device.id != exclusiveModeBlockedDeviceID else { return }
        do { try devices.acquireHogMode(on: device) } catch { report(error) }
        updateSignalPath()
    }

    private func releaseExclusiveAccess() {
        guard let device = outputDevice else { return }
        devices.releaseHogMode(on: device.id)
        updateSignalPath()
    }

    private func applyVolume() {
        switch settings.volumeMode {
        case .hardware:
            _ = try? player.setVolume(1.0) // unity gain: samples pass through untouched
            if let device = outputDevice {
                volume = devices.hardwareVolume(of: device.id) ?? 1.0
            }
        case .software:
            _ = try? player.setVolume(settings.softwareVolume)
            volume = settings.softwareVolume
        }
    }

    private func updateSignalPath(announce: Bool = true) {
        guard let format = currentFormat else {
            signalPath = nil
            return
        }
        let exclusive = outputDevice.map { devices.ownsHogMode($0.id) } ?? false
        let status = SignalPathStatus.evaluate(.init(
            format: format,
            dsdMode: settings.dsdMode,
            deviceSampleRate: deviceSampleRate,
            deviceBitDepth: deviceBitDepth,
            volumeMode: settings.volumeMode,
            softwareVolume: settings.softwareVolume,
            exclusiveMode: exclusive,
            isVirtualDevice: outputDevice?.isVirtual ?? false,
            equalizerActive: equalizer.isActive))
        guard status != signalPath else { return }
        signalPath = status
        if announce { emit(.signalPathChanged(status)) }
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshProgress()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func refreshProgress() {
        let new = PlaybackProgress(elapsed: player.currentTime ?? 0, duration: player.totalTime)
        if new != progress { progress = new }
    }

    private func emit(_ event: PlaybackEngineEvent) {
        eventHandler?(event)
    }
}
