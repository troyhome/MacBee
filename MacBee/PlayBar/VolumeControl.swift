import SwiftUI

/// Volume slider. In hardware mode it moves the device's own volume, which keeps playback bit-perfect.
struct VolumeControl: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let engine = player.engine
        let enabled = engine.settings.volumeMode == .software || engine.hardwareVolumeAvailable
        HStack(spacing: 4) {
            Image(systemName: icon(for: engine.volume))
                .font(.mbSecondary)
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18)
            Slider(value: Binding(get: { Double(engine.volume) }, set: { player.setVolume(Float($0)) }), in: 0...1)
                .controlSize(.mini)
                .frame(width: 80)
        }
        .disabled(!enabled)
        .help(enabled ? "Volume" : "This device has no volume control. Use the knob on your DAC.")
    }

    private func icon(for volume: Float) -> String {
        switch volume {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
