import MacBeeLibrary
import SwiftUI

/// "Edit Tags in TagBee…" for menus. Disabled, with a hint, when no tag editor is chosen.
struct EditTagsButton: View {
    /// The songs to edit (loaded when clicked, so albums don't load up front).
    let tracks: () async -> [Track]
    @Environment(AppModel.self) private var app

    init(tracks: [Track]) {
        self.tracks = { tracks }
    }

    init(tracks: @escaping () async -> [Track]) {
        self.tracks = tracks
    }

    var body: some View {
        if let editor = app.tagEditor, let name = editor.editorName {
            Button("Edit Tags in \(name)…") {
                Task { editor.editShowingProblems(await tracks()) }
            }
        } else {
            Button("Edit Tags… (choose an editor in Preferences)") {}
                .disabled(true)
        }
    }
}
