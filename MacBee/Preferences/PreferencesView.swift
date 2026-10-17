import SwiftUI

/// The Preferences window (⌘,).
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferences()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearancePreferences()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            LibraryPreferences()
                .tabItem { Label("Library", systemImage: "music.note.house") }
            AudioPreferences()
                .tabItem { Label("Audio", systemImage: "hifispeaker.2") }
            TagEditorPreferences()
                .tabItem { Label("Tag Editor", systemImage: "tag") }
        }
        .frame(width: 620)
        .frame(minHeight: 420)
    }
}

/// Grey explanation text under a setting.
struct PreferenceNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
