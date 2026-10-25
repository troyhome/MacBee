import MacBeeAudio
import SwiftUI

/// Output device, exclusive mode, volume, DSD and memory loading.
struct AudioPreferences: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let settings = player.engine.settings
        Form {
            Section("Output") {
                Picker("Output device", selection: binding(\.deviceUID)) {
                    Text("System Default").tag(String?.none)
                    ForEach(player.availableDevices()) { device in
                        Text(device.isVirtual ? "\(device.name) (virtual)" : device.name).tag(Optional(device.uid))
                    }
                }
                Toggle("Exclusive mode", isOn: binding(\.exclusiveMode))
                PreferenceNote("Stops other apps from playing through the same device while MacBee plays, so nothing mixes into your music. If another player already has the device to itself, MacBee names it; if the device won't start this way, MacBee plays shared instead.")
                Toggle("Use the highest bit depth the device supports", isOn: binding(\.preferHighestBitDepth))
                PreferenceNote("Keeps 24-bit music from being cut down to 16-bit. Leave on unless a DAC misbehaves.")
            }

            Section("Volume") {
                Picker("Volume control", selection: binding(\.volumeMode)) {
                    Text("Hardware (the device's own volume)").tag(VolumeMode.hardware)
                    Text("Software (inside MacBee)").tag(VolumeMode.software)
                }
                .pickerStyle(.radioGroup)
                PreferenceNote(settings.volumeMode == .hardware
                    ? "Bit-perfect: the music data reaches the device untouched, and the device turns it up or down."
                    : "Works with any device, but below 100% the music data is changed, so playback is not bit-perfect.")
            }

            Section("DSD files (.dsf)") {
                Picker("Play DSD as", selection: binding(\.dsdMode)) {
                    Text("Convert to PCM (works everywhere)").tag(DSDPlaybackMode.pcmConversion)
                    Text("DoP (bit-perfect, DAC must support it)").tag(DSDPlaybackMode.dop)
                }
                .pickerStyle(.radioGroup)
                if settings.dsdMode == .dop {
                    Label("Only use DoP with a DAC that supports it. Otherwise you'll hear loud noise.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.mbCaption)
                        .foregroundStyle(theme.warning)
                } else {
                    PreferenceNote("Conversion handles DSD64. DSD128 and higher need DoP.")
                }
            }

            Section("Network playback") {
                Toggle("Load each song into memory before it plays", isOn: binding(\.loadIntoMemory))
                PreferenceNote("Prevents dropouts when the network drive is slow or busy. Files over 1.5 GB are always read directly.")
            }
        }
        .formStyle(.grouped)
    }

    /// Reads a setting from the engine and saves changes back through the player.
    private func binding<Value>(_ keyPath: WritableKeyPath<OutputSettings, Value>) -> Binding<Value> {
        Binding(get: { player.engine.settings[keyPath: keyPath] },
                set: { value in player.updateOutputSettings { $0[keyPath: keyPath] = value } })
    }
}
