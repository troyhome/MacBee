// macbee-play — command-line harness for the Phase 1 engine.
//
//   swift run macbee-play --list-devices
//   swift run macbee-play [--exclusive] [--dop] [--software-volume 0.5] [--device "Name"] file1.flac file2.flac ...
//
// While playing, type: p (pause/resume), n (next), e (jump to last 10 seconds), s (stop and quit), +/- (volume).

import Foundation
import MacBeeAudio

/// Minimal queue so we can test gapless playback and sample-rate switching.
@MainActor
final class SimpleQueue: PlaybackQueueSource {
    let tracks: [URL]
    private(set) var index = 0

    init(_ tracks: [URL]) { self.tracks = tracks }

    var current: URL? { tracks.indices.contains(index) ? tracks[index] : nil }

    func track(after url: URL) -> URL? {
        guard let i = tracks.firstIndex(of: url), i + 1 < tracks.count else { return nil }
        return tracks[i + 1]
    }

    func engineDidAdvance(to url: URL) {
        if let i = tracks.firstIndex(of: url) { index = i }
    }

    func advance() -> URL? {
        index += 1
        return current
    }
}

struct Options {
    var listDevices = false
    var settings = OutputSettings.default
    var deviceName: String?
    var files: [URL] = []
}

func parse(_ args: [String]) -> Options {
    var o = Options()
    var it = args.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--list-devices": o.listDevices = true
        case "--exclusive": o.settings.exclusiveMode = true
        case "--dop": o.settings.dsdMode = .dop
        case "--software-volume":
            o.settings.volumeMode = .software
            o.settings.softwareVolume = Float(it.next() ?? "1") ?? 1
        case "--device": o.deviceName = it.next()
        default: o.files.append(URL(fileURLWithPath: (arg as NSString).expandingTildeInPath))
        }
    }
    return o
}

func describe(_ device: AudioDevice) -> String {
    let rates = device.supportedSampleRates.map { AudioFormatInfo.formatRate($0) }.joined(separator: ", ")
    return "\(device.name) [\(device.manufacturer)]  volume: \(device.hasHardwareVolume ? "hardware" : "none")\n    rates: \(rates)"
}

@MainActor
func run() {
    var options = parse(CommandLine.arguments)
    let engine = SFBPlaybackEngine(settings: options.settings)

    if options.listDevices {
        engine.availableOutputDevices().forEach { print("• " + describe($0)) }
        exit(0)
    }
    if let name = options.deviceName {
        guard let match = engine.availableOutputDevices().first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else {
            print("No device matching \"\(name)\". Use --list-devices."); exit(1)
        }
        options.settings.deviceUID = match.uid
        engine.apply(options.settings)
    }
    guard !options.files.isEmpty else {
        print("Usage: macbee-play [--exclusive] [--dop] [--software-volume 0.5] [--device NAME] files...")
        exit(1)
    }

    let queue = SimpleQueue(options.files)
    engine.queueSource = queue

    engine.eventHandler = { event in
        switch event {
        case let .trackStarted(url, format):
            print("\n▶ \(url.lastPathComponent)  —  \(format.displayString)")
            engine.signalPath?.summaryLines.forEach { print("  · \($0)") }
        case let .outputChanged(name, rate, bits):
            print("  output: \(name) @ \(AudioFormatInfo.formatRate(rate))\(bits.map { ", \($0)-bit" } ?? "")")
        case let .signalPathChanged(status):
            print("  signal path changed:")
            status.summaryLines.forEach { print("  · \($0)") }
        case let .stateChanged(state):
            print("  state: \(state)")
        case .queueFinished:
            print("\nQueue finished.")
            engine.shutdown()
            exit(0)
        case let .error(message):
            print("  ! \(message)")
        }
    }

    Task {
        do { try await engine.play(options.files[0]) } catch { print("! \(error.localizedDescription)"); exit(1) }
    }

    // Read single-letter commands from stdin.
    let input = FileHandle.standardInput
    input.readabilityHandler = { handle in
        let text = String(decoding: handle.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            switch text {
            case "p": engine.togglePlayPause()
            case "n":
                if let next = queue.advance() { try? await engine.play(next) } else { engine.shutdown(); exit(0) }
            case "e":
                if let duration = engine.progress.duration {
                    engine.seek(to: max(0, duration - 10))
                    print("  jumped to last 10 seconds")
                }
            case "s": engine.shutdown(); exit(0)
            case "+": engine.setVolume(engine.volume + 0.05); print("  volume \(Int(engine.volume * 100))%")
            case "-": engine.setVolume(engine.volume - 0.05); print("  volume \(Int(engine.volume * 100))%")
            default: break
            }
        }
    }
}

MainActor.assumeIsolated { run() }
dispatchMain()
