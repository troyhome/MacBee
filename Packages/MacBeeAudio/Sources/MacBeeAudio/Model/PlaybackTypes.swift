import Foundation

public enum PlaybackState: Sendable, Equatable {
    case stopped
    case paused
    case playing
}

/// Elapsed and total time for the scrubber.
public struct PlaybackProgress: Sendable, Equatable {
    public var elapsed: TimeInterval
    public var duration: TimeInterval?

    public init(elapsed: TimeInterval = 0, duration: TimeInterval? = nil) {
        self.elapsed = elapsed
        self.duration = duration
    }

    /// 0...1, or 0 when duration is unknown.
    public var fraction: Double {
        guard let d = duration, d > 0 else { return 0 }
        return min(max(elapsed / d, 0), 1)
    }
}

/// Events for logging and for parts of the app that prefer callbacks over observation.
public enum PlaybackEngineEvent: Sendable {
    case trackStarted(URL, AudioFormatInfo)
    case stateChanged(PlaybackState)
    case signalPathChanged(SignalPathStatus)
    case outputChanged(deviceName: String, sampleRate: Double, bitDepth: Int?)
    case queueFinished
    case error(String)
}

public enum AudioEngineError: LocalizedError {
    case hal(OSStatus, String)
    case unsupportedFile(URL)
    case decoderFailed(URL, String)
    case noOutputDevice
    case deviceBusy(String)
    case exclusiveModeUnavailable(String)
    case sampleRateChangeTimedOut(Double)

    public var errorDescription: String? {
        switch self {
        case let .hal(status, what): return "CoreAudio error \(status) while \(what)."
        case let .unsupportedFile(url): return "Unsupported file: \(url.lastPathComponent)"
        case let .decoderFailed(url, reason): return "Couldn't open \(url.lastPathComponent): \(reason)"
        case .noOutputDevice: return "No audio output device found."
        case let .deviceBusy(name): return "\(name) is in exclusive use by another app."
        case let .exclusiveModeUnavailable(name):
            return "Exclusive mode isn't available for \(name) in this version of MacBee. Music plays normally (shared)."
        case let .sampleRateChangeTimedOut(rate): return "The device didn't switch to \(AudioFormatInfo.formatRate(rate))."
        }
    }
}
