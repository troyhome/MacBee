import MacBeeAudio
import SwiftUI

/// The Equalizer window: on/off switch, presets, preamp and 16 band sliders.
struct EqualizerView: View {
    @Environment(EqualizerStore.self) private var eq
    @Environment(\.theme) private var theme
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sliders
            footer
        }
        .padding(18)
        .background(theme.background)
        .background(WindowLevelSetter(floating: true))
        .fixedSize()
        .alert("Save Preset", isPresented: $isNaming) {
            TextField("Preset name", text: $newName)
            Button("Save") { eq.saveCustomPreset(named: newName) }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || eq.isBuiltInName(newName))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(eq.isBuiltInName(newName)
                 ? "That name belongs to a built-in preset. Choose another name."
                 : "Saves the current sliders. Using the name of one of your presets replaces it.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Toggle("Equalizer", isOn: Binding(get: { eq.settings.isEnabled }, set: { eq.setEnabled($0) }))
                .toggleStyle(.switch)
                .font(.system(size: 13, weight: .semibold))
            presetMenu
            Spacer()
            Button("Save Preset…") {
                newName = eq.selectedPreset.flatMap { $0.isBuiltIn ? nil : $0.name } ?? ""
                isNaming = true
            }
            Button("Reset") { eq.choose(.flat) }
                .help("Puts every slider back to 0 dB (Flat)")
        }
    }

    private var presetMenu: some View {
        Menu(eq.presetTitle) {
            if !eq.customPresets.isEmpty {
                Section("My Presets") {
                    ForEach(eq.customPresets) { preset in
                        presetButton(preset)
                    }
                }
            }
            Section("Presets") {
                ForEach(EqualizerPreset.builtIns) { preset in
                    presetButton(preset)
                }
            }
            if !eq.customPresets.isEmpty {
                Divider()
                Menu("Delete Preset") {
                    ForEach(eq.customPresets) { preset in
                        Button(preset.name) { eq.deleteCustomPreset(preset) }
                    }
                }
            }
        }
        .frame(width: 150)
    }

    private func presetButton(_ preset: EqualizerPreset) -> some View {
        Button {
            eq.choose(preset)
        } label: {
            if eq.selectedPreset?.id == preset.id {
                Label(preset.name, systemImage: "checkmark")
            } else {
                Text(preset.name)
            }
        }
    }

    private var sliders: some View {
        HStack(alignment: .top, spacing: 4) {
            EQSlider(value: eq.settings.preamp, label: "Preamp", isEnabled: eq.settings.isEnabled,
                     width: 48) { eq.setPreamp($0) }
            Rectangle().fill(theme.separator).frame(width: 1, height: 200).padding(.horizontal, 6)
            ForEach(0..<EqualizerSettings.bandCount, id: \.self) { band in
                EQSlider(value: eq.settings.gains[band], label: Self.label(EqualizerSettings.frequencies[band]),
                         isEnabled: eq.settings.isEnabled) { eq.setGain($0, band: band) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface.opacity(0.5)))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(eq.isActive ? theme.warning : theme.good)
                .frame(width: 7, height: 7)
            Text(eq.isActive
                 ? "The equalizer is changing the sound, so playback is not bit-perfect."
                 : eq.settings.isEnabled
                    ? "All sliders are at 0 dB, so the equalizer is bypassed. Playback stays bit-perfect."
                    : "The equalizer is off and bypassed. Playback stays bit-perfect.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text("Lower the preamp if boosted songs distort.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }

    /// "25", "630", "1k", "1.6k", "16k".
    static func label(_ hz: Float) -> String {
        guard hz >= 1_000 else { return String(Int(hz)) }
        let k = hz / 1_000
        return k.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(k))k" : String(format: "%.1fk", k)
    }
}
