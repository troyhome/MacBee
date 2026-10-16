import SwiftUI

/// A titled block on the Home screen. Rows inside handle their own horizontal padding,
/// so horizontal scrollers can run edge to edge.
struct HomeSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.horizontal, 32)
            content
        }
    }
}
