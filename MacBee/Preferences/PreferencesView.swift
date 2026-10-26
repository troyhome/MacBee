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
        .frame(minWidth: 640, idealWidth: 680, maxWidth: .infinity, minHeight: 460, idealHeight: 720, maxHeight: .infinity)
        // Tighter rows, so more fits without scrolling.
        .environment(\.defaultMinListRowHeight, 24)
    }
}

/// A section title in Settings: bolder and brighter than the system's, so sections are easy to tell apart.
struct PreferenceHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, 2)
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
