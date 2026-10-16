import SwiftUI

/// Stand-in page for features coming in later phases.
struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}
