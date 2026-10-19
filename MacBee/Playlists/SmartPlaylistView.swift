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
            header
                .padding(.horizontal, 28)
                .padding(.top, 26)
            FilterField(prompt: "Filter tracks", text: $filter)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(smart.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("\(smart.subtitle) · \(tracks.count) songs, \(Format.minutes(tracks.map(\.duration).reduce(0, +)))")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            HStack(spacing: 12) {
                PillButton(title: "Play", systemImage: "play.fill", prominent: true) { player.play(shown) }
                    .disabled(tracks.isEmpty)
                PillButton(title: "Shuffle", systemImage: "shuffle", prominent: false) { player.playShuffled(shown) }
                    .disabled(tracks.isEmpty)
                Spacer()
                Button("Save as Playlist") {
                    Task { _ = await store.newPlaylist(with: shown) }
                }
                .disabled(tracks.isEmpty)
                .help("Make an ordinary playlist with these songs as they are now")
            }
        }
    }

    private var emptyText: String {
        switch smart {
        case .recentlyAdded: "Songs you add show up here."
        case .mostPlayed: "Songs you play show up here."
        case .topRated: "Heart songs to see them here."
        }
    }
}

/// A large rounded Play or Shuffle button (TIDAL style): white for the main action, dark for the other.
struct PillButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : theme.textPrimary)
                .frame(width: 140, height: 44)
                .background(Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.85 : 1) : (hovering ? theme.elevated : theme.surface)))
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accent)
                        .frame(width: 22)
                    Text(smart.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
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
