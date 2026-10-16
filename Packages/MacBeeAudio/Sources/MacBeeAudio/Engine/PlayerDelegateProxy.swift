import AVFoundation
import Foundation
import SFBAudioEngine

/// Receives SFBAudioEngine callbacks (on its own threads) and forwards
/// plain values to the engine on the main actor.
final class PlayerDelegateProxy: NSObject, AudioPlayer.Delegate {
    weak var engine: SFBPlaybackEngine?

    func audioPlayer(_ audioPlayer: AudioPlayer, decodingStarted decoder: PCMDecoding) {
        let url = decoder.inputSource.url
        Task { @MainActor [weak self] in self?.engine?.handleDecodingStarted(url) }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: PCMDecoding?) {
        let url = nowPlaying?.inputSource.url
        Task { @MainActor [weak self] in self?.engine?.handleNowPlayingChanged(url) }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        Task { @MainActor [weak self] in self?.engine?.handlePlaybackStateChanged() }
    }

    func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        Task { @MainActor [weak self] in self?.engine?.handleEndOfAudio() }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, decodingAborted decoder: PCMDecoding, error: Error,
                     framesRendered: AVAudioFramePosition) {
        let message = "Playback of \(decoder.inputSource.url?.lastPathComponent ?? "track") stopped: \(error.localizedDescription)"
        Task { @MainActor [weak self] in self?.engine?.report(message) }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.engine?.report(message) }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, audioEngineConfigurationChange userInfo: [AnyHashable: Any]?) {
        Task { @MainActor [weak self] in self?.engine?.handleOutputConfigurationChanged() }
    }
}
