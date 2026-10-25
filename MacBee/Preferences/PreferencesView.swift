import SwiftUI

/// The Preferences window (⌘,).
struct PreferencesView: View {
    /// The open tab; the Sync menu's "Device Sync…" opens the Sync tab.
    @AppStorage("preferencesTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralPreferences()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            AppearancePreferences()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag("appearance")
            LibraryPreferences()
                .tabItem { Label("Library", systemImage: "music.note.house") }
                .tag("library")
            AudioPreferences()
                .tabItem { Label("Audio", systemImage: "hifispeaker.2") }
                .tag("audio")
            TagEditorPreferences()
                .tabItem { Label("Tag Editor", systemImage: "tag") }
                .tag("tagEditor")
            SyncPreferences()
                .tabItem { Label("Device Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag("sync")
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
            .font(.mbCaption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
