import AppKit
import MacBeeLibrary
import SwiftUI

/// First-run screen: no music folders yet.
struct NoFoldersView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.house")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.accent)
            Text("Welcome to MacBee")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Text("Add the folder where your music lives. It can be on this Mac or a network drive.")
                .foregroundStyle(theme.textSecondary)
            Button("Add Music Folder…", action: chooseFolder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.warning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await library.addFolder(url) } catch { self.error = error.localizedDescription }
        }
    }
}
