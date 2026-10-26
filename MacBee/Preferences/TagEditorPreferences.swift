import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Choose the external tag editor app (TagBee) that songs open in.
struct TagEditorPreferences: View {
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        Form {
            Section(header: PreferenceHeader("Tag editor")) {
                if let path = preferences.tagEditorPath {
                    let url = URL(fileURLWithPath: path)
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(FileManager.default.displayName(atPath: path))
                            Text(path)
                                .font(.mbCaption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Open") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
                    }
                } else {
                    PreferenceNote("No tag editor chosen.")
                }
                HStack {
                    Button("Choose App…", action: chooseApp)
                    if preferences.tagEditorPath != nil {
                        Button("Clear") { preferences.tagEditorPath = nil }
                    }
                    Spacer()
                }
                PreferenceNote("Right-click songs or albums and choose Edit in TagBee, or use Track Studio. MacBee re-reads the songs as soon as you save them in this app.")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.tagEditorPath = url.path
    }
}
