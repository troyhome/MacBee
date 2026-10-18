import AVFoundation
import Foundation
import SFBAudioEngine

/// The 16-band EQ inside SFBAudioEngine's processing graph.
///
/// When the EQ is inactive (off, or all sliders at 0 dB) it is disconnected, so the graph is the plain
/// source → mixer path and playback stays bit-perfect. When active it sits between the source and the mixer.
///
/// Used from the main actor (`update`) and from the player's decoding thread (`reconnect`, during a
/// format change). Both run inside `modifyProcessingGraph` / the player's engine lock, so they never overlap.
final class EqualizerNode: @unchecked Sendable {
    let unit = AVAudioUnitEQ(numberOfBands: EqualizerSettings.bandCount)
    private var isAttached = false

    init() {
        for (band, frequency) in zip(unit.bands, EqualizerSettings.frequencies) {
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 0.9 // octaves; neighbouring bands overlap a little for smooth curves
            band.gain = 0
            band.bypass = false
        }
    }

    /// Applies `settings` and puts the EQ in or takes it out of the signal path.
    func update(_ settings: EqualizerSettings, player: AudioPlayer) {
        unit.globalGain = settings.preamp
        for (band, gain) in zip(unit.bands, settings.gains) { band.gain = gain }

        let source = player.sourceNode
        player.modifyProcessingGraph { [self] engine in
            if !isAttached {
                engine.attach(unit)
                isAttached = true
            }
            let format = source.outputFormat(forBus: 0)
            let inPath = engine.outputConnectionPoints(for: source, outputBus: 0).first?.node === unit
            if settings.isActive && !inPath {
                engine.disconnectNodeOutput(source)
                engine.connect(unit, to: engine.mainMixerNode, format: format)
                engine.connect(source, to: unit, format: format)
                limitBands(to: format.sampleRate)
            } else if !settings.isActive && inPath {
                engine.disconnectNodeOutput(source)
                engine.disconnectNodeOutput(unit)
                engine.connect(source, to: engine.mainMixerNode, format: format)
            }
        }
    }

    /// Called by the player when the track format changes while the EQ is in the path.
    /// Returns the node the source should connect to.
    func reconnect(in engine: AVAudioEngine, format: AVAudioFormat) -> AVAudioNode {
        engine.disconnectNodeOutput(unit)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        limitBands(to: format.sampleRate)
        return unit
    }

    /// Bands at or above the Nyquist limit can't be shaped; leave them out at low sample rates.
    private func limitBands(to sampleRate: Double) {
        for band in unit.bands {
            band.bypass = Double(band.frequency) >= sampleRate * 0.45
        }
    }
}
