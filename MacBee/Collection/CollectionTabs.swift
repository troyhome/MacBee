import SwiftUI

/// The Collections tabs: Playlists, Various Artists, Saved Mixes, then the liked Albums, Tracks and Videos
/// grouped together behind a heart.
struct CollectionTabs: View {
    @Binding var section: CollectionSection
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            group(CollectionSection.general)
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accent)
                    .padding(.leading, 10)
                    .help("Things you've liked")
                ForEach(CollectionSection.liked) { tab($0) }
            }
            .padding(3)
            .background(Capsule().fill(theme.surface))
        }
    }

    private func group(_ sections: [CollectionSection]) -> some View {
        HStack(spacing: 2) {
            ForEach(sections) { tab($0) }
        }
        .padding(3)
        .background(Capsule().fill(theme.surface))
    }

    private func tab(_ item: CollectionSection) -> some View {
        let selected = item == section
        return Button {
            section = item
        } label: {
            Text(item.title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? theme.onAccent : theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(selected ? theme.accent : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
