import SwiftUI

/// Gives a window everything the views need: models, library, theme. Used by the main window and the mini player.
struct AppEnvironment: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        let theme = model.themeStore.theme
        Group {
            if let library = model.library, let playlists = model.playlists {
                content.environment(library).environment(playlists)
            } else {
                content
            }
        }
        .environment(model)
        .environment(model.player)
        .environment(model.themeStore)
        .environment(model.preferences)
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
    }
}

extension View {
    func appEnvironment(_ model: AppModel) -> some View {
        modifier(AppEnvironment(model: model))
    }
}
