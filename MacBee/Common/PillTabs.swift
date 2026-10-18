import SwiftUI

/// A row of rounded tab buttons with icons, used across MacBee (Track Studio, Collections, Duplicates).
struct PillTabs<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let systemImage: (Item) -> String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                PillTab(title: title(item), systemImage: systemImage(item), isSelected: item == selection) {
                    selection = item
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.surface))
    }
}

/// One tab: icon and title, filled with the accent color when selected.
struct PillTab: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? theme.onAccent : theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(isSelected ? theme.accent : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
