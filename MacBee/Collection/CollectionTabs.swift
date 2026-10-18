import SwiftUI

/// The Collections tabs: Playlists, Various Artists, Saved Mixes, then the liked Albums, Tracks and Videos
/// grouped together behind a heart. Each tab has an icon.
struct CollectionTabs: View {
    @Binding var section: CollectionSection
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(CollectionSection.general) { tab($0) }
            }
            .padding(3)
            .background(Capsule().fill(theme.surface))
            HStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accent)
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .help("Things you've liked")
                ForEach(CollectionSection.liked) { tab($0) }
            }
            .padding(3)
            .background(Capsule().fill(theme.surface))
        }
    }

    private func tab(_ item: CollectionSection) -> some View {
        PillTab(title: item.title, systemImage: item.systemImage, isSelected: item == section) { section = item }
    }
}
