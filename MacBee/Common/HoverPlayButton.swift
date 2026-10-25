import SwiftUI

/// The round accent play button that appears on album artwork under the mouse.
struct HoverPlayButton: View {
    let action: () -> Void
    var help = "Play"

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 14))
                .foregroundStyle(theme.onAccent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(theme.accent))
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .padding(8)
        .help(help)
    }
}
