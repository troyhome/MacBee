import MacBeeLibrary
import SwiftUI

/// A mix shown in Playlist Studio's middle: a suggested mix, a saved mix, or one just made.
struct StudioMix: Identifiable, Equatable {
    enum Origin: Equatable { case suggested, saved(Int64), new }
    let id: String
    let title: String
    let subtitle: String
    let tracks: [Track]
    let origin: Origin

    var isSaved: Bool {
        if case .saved = origin { return true }
        return false
    }
}

/// Playlist Studio's list of mixes: today's suggestions (the same ones as on the Media page) and saved mixes.
/// Clicking one shows its songs, ready to drag into the playlist on the right.
struct StudioMixList: View {
    let onOpen: (StudioMix) -> Void

    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var suggested: [StudioMix] = []
    @State private var saved: [StudioMix] = []

    var body: some View {
        List {
            section("Suggested Mixes", suggested, empty: "No suggestions yet. They come from what you play and like.")
            section("Saved Mixes", saved, empty: "Mixes you save show up here.")
        }
        .scrollContentBackground(.hidden)
        .task(id: library.revision) {
            let database = library.database
            suggested = ((try? await database.suggestedMixes(day: SuggestedMixes.day)) ?? []).map {
                StudioMix(id: "s-\($0.id)", title: $0.title, subtitle: $0.subtitle, tracks: $0.tracks, origin: .suggested)
            }
            saved = ((try? await database.savedMixes()) ?? []).map {
                StudioMix(id: "m-\($0.id)", title: $0.title, subtitle: $0.subtitle, tracks: $0.tracks, origin: .saved($0.id))
            }
        }
    }

    /// Up to four different covers, in song order.
    private func firstCovers(_ mix: StudioMix) -> [Int64] {
        var seen = Set<Int64>()
        return Array(mix.tracks.compactMap(\.artworkId).filter { seen.insert($0).inserted }.prefix(4))
    }

    @ViewBuilder
    private func section(_ title: String, _ mixes: [StudioMix], empty: String) -> some View {
        Section {
            if mixes.isEmpty {
                Text(empty).font(.mbSecondary).foregroundStyle(theme.textSecondary)
            }
            ForEach(mixes) { mix in
                Button { onOpen(mix) } label: {
                    HStack(spacing: 12) {
                        ArtworkCollage(artworkIds: firstCovers(mix), size: 40, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mix.title).font(.mbRowTitle).foregroundStyle(theme.textPrimary)
                            Text("\(mix.subtitle) · \(mix.tracks.count) songs")
                                .font(.mbSecondary).foregroundStyle(theme.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(title).font(.mbSection).foregroundStyle(theme.textPrimary).padding(.top, 6)
        }
    }
}
