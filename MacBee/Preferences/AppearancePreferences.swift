import SwiftUI

struct AppearancePreferences: View {
    @Environment(ThemeStore.self) private var themeStore
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        @Bindable var themeStore = themeStore
        @Bindable var preferences = preferences
        Form {
            Section("Theme") {
                Picker("Theme", selection: $themeStore.kind) {
                    ForEach(ThemeKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Accent color") {
                HStack(spacing: 12) {
                    ForEach(AccentChoice.allCases.filter { $0 != .custom }) { choice in
                        AccentSwatch(color: choice.color, isSelected: themeStore.accent == choice) {
                            themeStore.accent = choice
                        }
                    }
                    Divider().frame(height: 22)
                    ColorPicker("Custom", selection: Binding(
                        get: { Color(hex: themeStore.customAccentHex) },
                        set: { color in
                            themeStore.customAccentHex = color.hexValue
                            themeStore.accent = .custom
                        }), supportsOpacity: false)
                    if themeStore.accent == .custom {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                PreferenceNote("Used for buttons, highlights and the playing song.")
            }
            Section("Library display") {
                Toggle("Show quality badges (e.g. FLAC 24/96)", isOn: $preferences.showQualityBadges)
                Toggle("Hide compilation-only artists from Artists", isOn: $preferences.hideCompilationOnlyArtists)
                PreferenceNote("Leaves out artists who only appear on compilations, unless they also have an album of their own.")
            }
            Section("Sidebar") {
                Slider(value: $preferences.sidebarWidth, in: PreferencesStore.sidebarWidthRange, step: 2) {
                    Text("Width")
                } minimumValueLabel: {
                    Text("Narrow")
                } maximumValueLabel: {
                    Text("Wide")
                }
                PreferenceNote("The width when the sidebar is expanded. Collapsed, it always shows icons only.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccentSwatch: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.primary, lineWidth: isSelected ? 2 : 0).padding(-3))
        }
        .buttonStyle(.plain)
    }
}
