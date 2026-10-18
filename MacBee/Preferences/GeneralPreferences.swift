import SwiftUI

struct GeneralPreferences: View {
    @Environment(PreferencesStore.self) private var preferences
    @Environment(AppModel.self) private var app

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
            Section("Media keys") {
                Toggle("Media keys always control MacBee", isOn: $preferences.mediaKeysAlwaysMacBee)
                    .onChange(of: preferences.mediaKeysAlwaysMacBee) { _, on in
                        on ? app.mediaKeys.start(askForPermission: true) : app.mediaKeys.stop()
                    }
                if preferences.mediaKeysAlwaysMacBee && !app.mediaKeys.isActive {
                    HStack {
                        Text("Needs the Accessibility permission")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings") { openAccessibilitySettings() }
                    }
                }
                PreferenceNote("While MacBee has music loaded, play/pause, next and previous go to MacBee even if Qobuz, Spotify or Apple Music is open. To allow it, turn MacBee on in System Settings > Privacy & Security > Accessibility.")
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

    private func openAccessibilitySettings() {
        app.mediaKeys.start(askForPermission: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
