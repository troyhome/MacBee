import Foundation
import MacBeeAudio
import Observation

/// The equalizer's sliders, the chosen preset and the user's own presets. Saved between launches (per Mac)
/// and passed to the engine on every change.
@MainActor
@Observable
final class EqualizerStore {
    private(set) var settings: EqualizerSettings
    private(set) var customPresets: [EqualizerPreset]
    /// The preset last chosen or saved; nil once the sliders were moved away from it.
    private(set) var selectedPresetId: UUID?

    @ObservationIgnored private let engine: any PlaybackEngine
    private static let settingsKey = "equalizer"
    private static let presetsKey = "equalizerPresets"
    private static let selectedKey = "equalizerPreset"

    init(engine: any PlaybackEngine) {
        self.engine = engine
        let d = UserDefaults.standard
        settings = d.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(EqualizerSettings.self, from: $0) } ?? .off
        customPresets = d.data(forKey: Self.presetsKey)
            .flatMap { try? JSONDecoder().decode([EqualizerPreset].self, from: $0) } ?? []
        selectedPresetId = d.string(forKey: Self.selectedKey).flatMap(UUID.init) ?? EqualizerPreset.flat.id
        engine.applyEqualizer(settings)
    }

    var allPresets: [EqualizerPreset] { EqualizerPreset.builtIns + customPresets }

    var selectedPreset: EqualizerPreset? {
        guard let id = selectedPresetId else { return nil }
        return allPresets.first { $0.id == id && settings.matches($0) }
    }

    /// Shown on the preset menu: the preset's name, or "Custom" after moving sliders.
    var presetTitle: String { selectedPreset?.name ?? "Custom" }

    var isActive: Bool { settings.isActive }

    func setEnabled(_ on: Bool) {
        settings.isEnabled = on
        commit()
    }

    func setPreamp(_ dB: Float) {
        settings.preamp = Self.rounded(dB)
        commit()
    }

    func setGain(_ dB: Float, band: Int) {
        guard settings.gains.indices.contains(band) else { return }
        settings.gains[band] = Self.rounded(dB)
        commit()
    }

    /// Choosing a preset also turns the EQ on (except Flat, which leaves the switch alone).
    func choose(_ preset: EqualizerPreset) {
        settings.apply(preset)
        if preset != .flat { settings.isEnabled = true }
        selectedPresetId = preset.id
        commit()
    }

    /// Saves the current sliders as a new preset, or overwrites a custom preset with the same name.
    func saveCustomPreset(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let i = customPresets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            customPresets[i].preamp = settings.preamp
            customPresets[i].gains = settings.gains
            selectedPresetId = customPresets[i].id
        } else {
            let preset = EqualizerPreset(name: name, preamp: settings.preamp, gains: settings.gains)
            customPresets.append(preset)
            selectedPresetId = preset.id
        }
        commit()
    }

    func deleteCustomPreset(_ preset: EqualizerPreset) {
        guard !preset.isBuiltIn else { return }
        customPresets.removeAll { $0.id == preset.id }
        if selectedPresetId == preset.id { selectedPresetId = nil }
        commit()
    }

    /// True when `name` is a built-in preset's name (those can't be overwritten).
    func isBuiltInName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return EqualizerPreset.builtIns.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func commit() {
        engine.applyEqualizer(settings)
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(settings) { d.set(data, forKey: Self.settingsKey) }
        if let data = try? JSONEncoder().encode(customPresets) { d.set(data, forKey: Self.presetsKey) }
        d.set(selectedPresetId?.uuidString, forKey: Self.selectedKey)
    }

    /// Half-dB steps keep the numbers readable.
    private static func rounded(_ dB: Float) -> Float { (dB * 2).rounded() / 2 }
}
