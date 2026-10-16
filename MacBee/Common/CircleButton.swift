import SwiftUI

/// Round icon button (Play, Shuffle, Add, Back).
struct CircleButton: View {
    let systemImage: String
    let help: String
    var tinted = true
    var diameter: CGFloat = 34
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.41, weight: .semibold))
                .foregroundStyle(tinted ? theme.accent : theme.textPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(hovering ? theme.elevated : theme.surface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
