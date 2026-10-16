import Foundation
import MacBeeAudio

/// Remembers output settings (device, exclusive mode, volume mode) between launches.
/// Phase 6 replaces this with the full PreferencesStore.
enum OutputSettingsStore {
    private static let key = "outputSettings"

    static func load() -> OutputSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(OutputSettings.self, from: data) else { return .default }
        return settings
    }

    static func save(_ settings: OutputSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
