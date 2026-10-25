import MacBeeLibrary
import SwiftUI

/// A smart playlist's page (Favorites, Recently Added, Most Played), laid out like TIDAL's Tracks page: big
/// Play and Shuffle buttons, a filter box, and a table of songs with covers, sortable columns, and + and heart
/// on every row. Songs are refilled from the library each time; "Save as Playlist" keeps a copy of today's list.
struct SmartPlaylistView: View {
    let smart: SmartPlaylist

    @Environment(MusicLibrary.self) private var library
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var tracks: [Track] = []
    @State private var added: [Int64: Date] = [:]
    @State private var filter = ""
    @State private var sort = TrackTableSort()

    /// The songs as shown: filtered, then sorted by the chosen column.
    private var shown: [Track] {
        let words = filter.lowercased().split(separator: " ").map(String.init)
        let matching = words.isEmpty ? tracks : tracks.filter { track in
            let text = "\(track.displayTitle) \(track.displayArtist) \(track.displayAlbum)".lowercased()
            return words.allSatisfy(text.contains)
        }
        return sort.apply(to: matching, added: dateAdded)
    }

    var body: some View {
        let shown = shown
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: smart.title,
                       subtitle: "\(smart.subtitle) · \(tracks.count) songs, \(Format.minutes(tracks.map(\.duration).reduce(0, +)))") {
                PlayControls(onPlay: { player.play(shown) }, onShuffle: { player.playShuffled(shown) }, large: false) {
                    Button("Play Next") { player.playNext(shown) }
                    Button("Add to Queue") { player.addToQueue(shown) }
                    Divider()
                    Button("Save as Playlist") { Task { _ = await store.newPlaylist(with: shown) } }
                }
                .disabled(tracks.isEmpty)
                HeaderDivider()
                FilterField(prompt: "Filter songs", text: $filter)
                    .frame(minWidth: 120, maxWidth: 220)
            }
            .padding(.bottom, 8)
            TrackTable(tracks: shown, sort: $sort, dateAdded: dateAdded) { index in
                player.play(shown, startAt: index)
            }
            .overlay {
                if tracks.isEmpty {
                    ContentUnavailableView(smart.title, systemImage: smart.systemImage, description: Text(emptyText))
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
        }
        .navigationTitle(smart.title)
        .task(id: "\(smart.rawValue)-\(library.revision)-\(player.playsRecorded)-\(player.favoritesSaved)") {
            tracks = (try? await library.database.tracks(for: smart)) ?? []
            if smart == .topRated { added = (try? await library.database.favoritedDates()) ?? [:] }
        }
    }

    /// Favorites: when the song was hearted. Otherwise when it was added to the library.
    private func dateAdded(_ track: Track) -> Date {
        if smart == .topRated, let id = track.id, let date = added[id] { return date }
        return track.dateAdded
    }

    private var emptyText: String {
        switch smart {
        case .recentlyAdded: "Songs you add show up here."
        case .mostPlayed: "Songs you play show up here."
        case .topRated: "Heart songs to see them here."
        }
    }
}

/// The smart playlists at the top of the sidebar's playlists.
struct SmartPlaylistRows: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        ForEach(SmartPlaylist.allCases) { smart in
            let selected = isSelected(smart)
            Button {
                app.selectPlaylistInSidebar(smart.playlistId)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: smart.systemImage)
                        .font(.mbSecondary)
                        .foregroundStyle(theme.accent)
                        .frame(width: 22)
                    Text(smart.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? theme.elevated : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .draggable(DragPayload.playlist(smart.playlistId).string)
            .help(smart.subtitle)
        }
    }

    private func isSelected(_ smart: SmartPlaylist) -> Bool {
        app.isPlaylistHighlighted(smart.playlistId)
    }
}
