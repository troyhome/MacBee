import SwiftUI

/// Small icon button used in the play bar.
struct BarIconButton: View {
    let systemImage: String
    let help: String
    var isActive = false
    var size: CGFloat = 14
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundStyle(isActive ? theme.accent : (hovering ? theme.textPrimary : theme.textSecondary))
                .frame(width: size + 14, height: size + 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
