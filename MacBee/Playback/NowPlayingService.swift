import AppKit
import MacBeeLibrary
import MediaPlayer

/// Connects MacBee to the keyboard's media keys and the "Now Playing" panel in Control Center
/// (title, artist, cover, position, and play/pause/next/previous/seek from there).
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
        // Refresh once a second; the system moves the position smoothly in between.
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.update()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Commands from media keys and Control Center

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run { $0.togglePlayPause() } ?? .commandFailed }
        center.playCommand.addTarget { [weak self] _ in
            self?.run { if !$0.isPlaying { $0.togglePlayPause() } } ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.run { if $0.isPlaying { $0.togglePlayPause() } } ?? .commandFailed
        }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.next() } ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.previous() } ?? .commandFailed }
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
        if artwork?.trackPath != track.path {
            artwork = (track.path, await loadArtwork(for: track))
        }
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
        switch player.engine.state {
        case .playing: center.playbackState = .playing
        case .paused: center.playbackState = .paused
        case .stopped: center.playbackState = .stopped
        }
    }

    private func loadArtwork(for track: Track) async -> MPMediaItemArtwork? {
        guard let library, let url = await library.artworkURL(for: track.artworkId),
              let image = NSImage(contentsOf: url) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
