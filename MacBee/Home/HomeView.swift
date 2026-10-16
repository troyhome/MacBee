import MacBeeLibrary
import SwiftUI

/// The Music (Home) screen: stats, recently played/added, mixes, forgotten gems, play history, library status.
struct HomeView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var model = HomeViewModel()

    var body: some View {
        Group {
            // Wait until the first load so the welcome screen doesn't flash on launch.
            if model.isLoaded && library.folders.isEmpty && library.stats.tracks == 0 {
                NoFoldersView()
            } else {
                content
            }
        }
        .navigationTitle("Music")
        .task(id: "\(library.revision)-\(player.playsRecorded)") {
            await model.load(from: library.database)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                Text("Music")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 32)

                StatCardsRow(stats: library.stats)
                    .padding(.horizontal, 32)

                HomeSection(title: "Recently Played") {
                    if model.recentlyPlayed.isEmpty {
                        EmptyRowMessage(model.isLoaded ? "Albums you play will show up here." : "")
                    } else {
                        AlbumCardRow(albums: model.recentlyPlayed)
                    }
                }

                if !model.mixes.isEmpty {
                    HomeSection(title: "Suggested Mixes", subtitle: "New picks every day") {
                        MixRow(mixes: model.mixes)
                    }
                }

                if !model.recentlyAdded.isEmpty {
                    HomeSection(title: "Recently Added") {
                        AlbumCardRow(albums: model.recentlyAdded)
                    }
                }

                if !model.forgottenGems.isEmpty {
                    HomeSection(title: "Forgotten Gems", subtitle: "Albums you loved but haven't played in a while") {
                        AlbumCardRow(albums: model.forgottenGems)
                    }
                }

                HomeSection(title: "Play History") {
                    if model.historyDays.isEmpty {
                        EmptyRowMessage(model.isLoaded ? "No plays yet. Songs count once you've heard half (or 4 minutes)." : "")
                    } else {
                        PlayHistoryList(days: model.historyDays,
                                        canLoadMore: model.canLoadMoreHistory) {
                            Task { await model.loadMoreHistory(from: library.database) }
                        }
                        .padding(.horizontal, 32)
                    }
                }

                HomeSection(title: "Library") {
                    LibraryStatusPanel()
                        .padding(.horizontal, 32)
                }
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
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
