import SwiftUI

@main
struct MacBeeApp: App {
    static let mainWindowID = "main"
    static let miniPlayerWindowID = "mini"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("MacBee", id: Self.mainWindowID) {
            RootView()
                .background(WindowReopener(delegate: appDelegate, player: model.player))
                .appEnvironment(model)
                .frame(minWidth: 960, minHeight: 600)
                .task { await model.start() }
        }
        .commands {
            AboutCommand()
            PlaybackCommands(player: model.player, preferences: model.preferences)
            CommandGroup(after: .textEditing) {
                Button("Search") { model.focusSearch() }
                    .keyboardShortcut("f")
            }
        }

        Settings {
            PreferencesView()
                .appEnvironment(model)
        }

        Window("Mini Player", id: Self.miniPlayerWindowID) {
            MiniPlayerView()
                .appEnvironment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}
