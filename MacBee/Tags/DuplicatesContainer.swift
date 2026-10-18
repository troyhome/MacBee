import SwiftUI

/// The Duplicates tab: songs or videos with more than one copy.
struct DuplicatesContainer: View {
    @AppStorage("duplicatesKind") private var kind: Kind = .songs

    enum Kind: String, CaseIterable, Identifiable {
        case songs, videos
        var id: String { rawValue }
        var title: String { self == .songs ? "Songs" : "Videos" }
        var systemImage: String { self == .songs ? "music.note" : "film" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PillTabs(items: Kind.allCases, selection: $kind, title: \.title, systemImage: \.systemImage)
                .padding(.horizontal, 28)
            .padding(.top, 6)
            switch kind {
            case .songs: SongDuplicatesView()
            case .videos: VideoDuplicatesView()
            }
        }
    }
}
