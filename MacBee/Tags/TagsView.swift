import MacBeeLibrary
import SwiftUI

/// The Track Studio page (sidebar item "tags" in code): tools for keeping the library tidy. Duplicates lists
/// songs and videos with more than one copy;
/// TagBee opens the tag editor (fuller TagBee integration comes in roadmap Phase 5).
struct TagsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @AppStorage("tagsSection") private var section: TagsSection = .duplicates

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    if app.canGoBack {
                        CircleButton(systemImage: "chevron.left", help: "Back", tinted: false) { app.goBack() }
                    }
                    Text("Track Studio")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                }
                Picker("Show", selection: $section) {
                    ForEach(TagsSection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 8)

            switch section {
            case .duplicates: DuplicatesContainer()
            case .tagBee: TagBeePanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Track Studio")
    }
}

enum TagsSection: String, CaseIterable, Identifiable {
    case duplicates, tagBee
    var id: String { rawValue }
    var title: String { self == .duplicates ? "Duplicates" : "TagBee" }
}

/// For now: open TagBee. Roadmap Phase 5 connects it more closely.
private struct TagBeePanel: View {
    @Environment(AppModel.self) private var app
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        ContentUnavailableView {
            Label("TagBee", systemImage: "tag")
        } description: {
            Text("Edit tags in TagBee: right-click songs or albums and choose Edit Tags in TagBee, or open it here.")
        } actions: {
            Button("Open TagBee") {
                if let path = preferences.tagEditorPath { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            }
            .disabled(preferences.tagEditorPath == nil)
        }
    }
}
