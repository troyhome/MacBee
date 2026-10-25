import SwiftUI

/// A titled block on the Home screen. Rows inside handle their own horizontal padding,
/// so horizontal scrollers can run edge to edge.
struct HomeSection<Content: View>: View {
    let title: String
    var subtitle: String?
    /// An optional button at the right of the title (e.g. Refresh Suggestions).
    var action: (title: String, systemImage: String, run: () -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    init(title: String, subtitle: String? = nil, action: (title: String, systemImage: String, run: () -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.mbSection)
                        .foregroundStyle(theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.mbSecondary)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer()
                if let action {
                    Button(action: action.run) { Label(action.title, systemImage: action.systemImage) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, PageLayout.margin)
            content
        }
    }
}
