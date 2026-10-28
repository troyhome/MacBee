import AppKit
import MacBeeLibrary
import MediaPlayer

/// Connects MacBee to the keyboard's media keys and the "Now Playing" panel in Control Center
/// (title, artist, cover, position, and play/pause/next/previous/seek from there).
///
/// macOS sends the media keys to whichever app most recently reported that it's playing. So the moment
/// MacBee starts or resumes playback it reports itself as playing (not up to a second later), which takes
/// the keys away from Apple Music, Spotify and others. While paused it stays the "Now Playing" app, so
/// the play key resumes MacBee rather than waking another player.
@MainActor
final class NowPlayingService {
    private let player: PlayerViewModel
    private let library: MusicLibrary?
    private var updateTask: Task<Void, Never>?
    /// Cover for the current track, loaded once per track.
    private var artwork: (trackPath: String, item: MPMediaItemArtwork?)?

    init(player: PlayerViewModel, library: MusicLibrary?) {
        self.player = player
        self.library = library
        registerCommands()
        observePlayback()
        // Refresh once a second; the system moves the position smoothly in between.
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.update()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Commands from media keys and Control Center

    /// Reports to the system right away whenever playback starts, pauses or moves to another song.
    private func observePlayback() {
        withObservationTracking {
            _ = player.isPlaying
            _ = player.currentTrack?.path
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.update()
                self.observePlayback()
            }
        }
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        // Only the commands MacBee handles are on, so the system doesn't offer buttons that do nothing.
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand] {
            command.isEnabled = true
        }
        for command in [center.stopCommand, center.skipForwardCommand, center.skipBackwardCommand,
                        center.seekForwardCommand, center.seekBackwardCommand, center.changePlaybackRateCommand,
                        center.ratingCommand, center.likeCommand, center.dislikeCommand, center.bookmarkCommand] {
            command.isEnabled = false
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run { $0.togglePlayPause() } ?? .commandFailed }
        center.playCommand.addTarget { [weak self] _ in
            self?.run { if !$0.isPlaying { $0.togglePlayPause() } } ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.run { if $0.isPlaying { $0.togglePlayPause() } } ?? .commandFailed
        }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.forwardButton() } ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.backButton() } ?? .commandFailed }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.run { $0.engine.seek(to: event.positionTime) } ?? .commandFailed
        }
    }

    /// Commands arrive on the main thread.
    private nonisolated func run(_ action: @escaping @MainActor (PlayerViewModel) -> Void) -> MPRemoteCommandHandlerStatus {
        MainActor.assumeIsolated {
            guard player.currentTrack != nil else { return .noActionableNowPlayingItem }
            action(player)
            return .success
        }
    }

    // MARK: - Now Playing info

    private func update() async {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = player.currentTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        let newTrack = artwork?.trackPath != track.path
        if newTrack { artwork = (track.path, nil) }
        publish(track, to: center)
        // A new song's cover loads after the song is announced, so the media keys are claimed without delay.
        if newTrack {
            let item = await loadArtwork(for: track)
            guard player.currentTrack?.path == track.path else { return }
            artwork = (track.path, item)
            publish(track, to: center)
        }
    }

    private func publish(_ track: Track, to center: MPNowPlayingInfoCenter) {
        let progress = player.engine.progress
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPMediaItemPropertyAlbumTitle: track.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: progress.duration ?? track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let item = artwork?.item { info[MPMediaItemPropertyArtwork] = item }
        center.nowPlayingInfo = info
        // A song is loaded, so MacBee never reports "stopped" here. The engine stops for a moment between
        // songs (and when a sample-rate switch restarts the output), and "stopped" lets macOS hand the
        // media keys to another player. "Paused" keeps MacBee the Now Playing app, so play resumes it.
        center.playbackState = player.engine.state == .playing ? .playing : .paused
    }

    private func loadArtwork(for track: Track) async -> MPMediaItemArtwork? {
        guard let library, let url = await library.artworkURL(for: track.artworkId),
              let image = NSImage(contentsOf: url) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
