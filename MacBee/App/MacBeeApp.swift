import SwiftUI

@main
struct MacBeeApp: App {
    static let mainWindowID = "main"
    static let miniPlayerWindowID = "mini"
    static let equalizerWindowID = "equalizer"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("MacBee", id: Self.mainWindowID) {
            RootView()
                .background(WindowReopener(delegate: appDelegate, player: model.player))
                .appEnvironment(model)
                // Wide enough for the sidebar (whatever width it's dragged to) and the widest page, so nothing is cut off.
                .frame(minWidth: 820 + model.preferences.sidebarWidth, minHeight: 600)
                .task { await model.start() }
        }
        .commands {
            AboutCommand()
            PlaybackCommands(player: model.player, preferences: model.preferences, equalizer: model.equalizer)
            SyncCommands(app: model)
            CommandGroup(after: .textEditing) {
                Button("Search") { model.focusSearch() }
                    .keyboardShortcut("f")
            }
        }

        Settings {
            PreferencesView()
                .appEnvironment(model)
        }
        .windowResizability(.contentMinSize) // drag the bottom edge to make Settings taller

        Window("Mini Player", id: Self.miniPlayerWindowID) {
            MiniPlayerView()
                .appEnvironment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Window("Equalizer", id: Self.equalizerWindowID) {
            EqualizerView()
                .appEnvironment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
