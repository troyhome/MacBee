import MacBeeLibrary
import SwiftUI

/// The Music (Home) screen: stats, recently played/added, mixes, forgotten gems, play history, library status.
struct HomeView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.theme) private var theme
    @State private var model = HomeViewModel()
    @State private var confirmHistoryReset = false

    var body: some View {
        Group {
            // Wait until the first load so the welcome screen doesn't flash on launch.
            if model.isLoaded && library.folders.isEmpty && library.stats.tracks == 0 {
                NoFoldersView()
            } else {
                content
            }
        }
        .navigationTitle("Media")
        .confirmationDialog("Reset Play History?", isPresented: $confirmHistoryReset) {
            Button("Reset Play History", role: .destructive) {
                Task { await model.resetPlayHistory(in: library.database) }
            }
        } message: {
            Text("This deletes the list of what you played and when, on this Mac. Play counts and Most Played stay as they are. This can't be undone. (If you sync with another Mac, its history may come back with the next Combine.)")
        }
        .task(id: "\(library.revision)-\(player.playsRecorded)") {
            await model.load(from: library.database)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                HStack {
                    Text("Media")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    SourceBadge()
                }
                .padding(.horizontal, 32)

                ForEach(preferences.homeOrder.filter { !preferences.homeHidden.contains($0) }) { kind in
                    section(kind)
                }
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension HomeView {
    /// One block of the page; the order comes from Settings > General.
    @ViewBuilder
    func section(_ kind: HomeSectionKind) -> some View {
        switch kind {
        case .stats:
            StatCardsRow(stats: library.stats)
                .padding(.horizontal, 32)
        case .recentlyPlayed:
            HomeSection(title: "Recently Played",
                        action: ("Clear", "xmark.circle", { model.clearRecentlyPlayed() })) {
                if model.recentlyPlayed.isEmpty {
                    EmptyRowMessage(model.isLoaded ? "Albums you play will show up here." : "")
                } else {
                    AlbumCardRow(albums: model.recentlyPlayed)
                }
            }
        case .suggestedMixes:
            if !model.mixes.isEmpty {
                HomeSection(title: "Suggested Mixes", subtitle: "New picks every day",
                            action: ("Refresh Suggestions", "arrow.clockwise",
                                     { Task { await model.refreshMixes(from: library.database) } })) {
                    MixRow(mixes: model.mixes)
                }
            }
        case .recentlyAdded:
            HomeSection(title: "Recently Added",
                        action: ("Reset", "arrow.counterclockwise", { model.resetRecentlyAdded() })) {
                if model.recentlyAdded.isEmpty {
                    EmptyRowMessage(model.isLoaded ? "Music added from now on shows up here." : "")
                } else {
                    AlbumCardRow(albums: model.recentlyAdded)
                }
            }
        case .forgottenGems:
            if !model.forgottenGems.isEmpty {
                HomeSection(title: "Forgotten Gems", subtitle: "Albums you loved but haven't played in a while") {
                    AlbumCardRow(albums: model.forgottenGems)
                }
            }
        case .playHistory:
            HomeSection(title: "Play History",
                        action: ("Reset", "arrow.counterclockwise", { confirmHistoryReset = true })) {
                if model.historyDays.isEmpty {
                    EmptyRowMessage(model.isLoaded ? "No plays yet. Songs count once you've heard half (or 4 minutes)." : "")
                } else {
                    // About 10 songs tall; scroll inside it for the rest.
                    ScrollView {
                        PlayHistoryList(days: model.historyDays,
                                        canLoadMore: model.canLoadMoreHistory) {
                            Task { await model.loadMoreHistory(from: library.database) }
                        }
                        .padding(.trailing, 12)
                    }
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(height: 500)
                    .padding(.horizontal, 32)
                }
            }
        case .library:
            HomeSection(title: "Library") {
                LibraryStatusPanel()
                    .padding(.horizontal, 32)
            }
        }
    }
}

private struct EmptyRowMessage: View {
    let text: String
    @Environment(\.theme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 32)
    }
}
