import SwiftUI
import MacBeeLibrary

/// Opens the songs selected in the studio's library list in the tag editor (TagBee).
/// MacBee re-reads them after you save there.
struct TagEditorSlot: View {
    /// Songs selected in the middle pane.
    let selectedTracks: [Track]

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        let editor = app.tagEditor
        let name = editor?.editorName
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                Text(name.map { "Tag Editor · \($0)" } ?? "Tag Editor")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(selectedTracks.count > 1 ? "Edit \(selectedTracks.count) Songs…" : "Edit Tags…") {
                    editor?.editShowingProblems(selectedTracks)
                }
                .disabled(name == nil || selectedTracks.isEmpty)
                .controlSize(.small)
            }
            .foregroundStyle(theme.textSecondary)
            Text(message(editorName: name))
                .font(.mbCaption)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func message(editorName: String?) -> String {
        guard let editorName else { return "Choose your tag editor in Preferences → Tag Editor." }
        return selectedTracks.isEmpty
            ? "Select songs on the left, then click Edit Tags. MacBee updates them as soon as you save in \(editorName)."
            : "MacBee updates the songs as soon as you save in \(editorName)."
    }
}
