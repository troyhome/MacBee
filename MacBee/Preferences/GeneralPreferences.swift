import SwiftUI

struct GeneralPreferences: View {
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("When MacBee opens") {
                Picker("Show", selection: $preferences.startPage) {
                    ForEach(StartPage.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Check the library for changes", isOn: $preferences.checkLibraryAtLaunch)
                PreferenceNote("Looks for new, changed and removed files. Only sizes and dates are compared, so it's quick even on a network drive.")
            }
            Section("Display") {
                Toggle("Show quality badges (e.g. FLAC 24/96)", isOn: $preferences.showQualityBadges)
            }
            Section("Play counts") {
                Picker("Count a song as played", selection: $preferences.playCountRule) {
                    ForEach(PlayCountRule.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                PreferenceNote("Used for play counts, Recently Played, Most Played and Play History.")
            }
        }
        .formStyle(.grouped)
    }
}
