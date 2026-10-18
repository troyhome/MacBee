import MacBeeLibrary
import SwiftUI

/// A smart playlist's page: its songs (refilled from the library each time), Play, Shuffle, and
/// "Save as Playlist" to keep a copy of today's list.
struct SmartPlaylistView: View {
    let smart: SmartPlaylist

    @Environment(MusicLibrary.self) private var library
    @Environment(PlaylistStore.self) private var store
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var tracks: [Track] = []
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 10)
            List(selection: $selection) {
                ForEach(tracks, id: \.path) { track in
                    TrackRow(track: track, showsArtist: true,
                             isCurrent: player.currentTrack?.path == track.path,
                             isPlaying: player.isPlaying, isFavorite: player.isFavorite(track))
                        .tag(track.path)
                        .draggable(DragPayload.tracks([track.id].compactMap { $0 }).string)
                }
            }
            .contextMenu(forSelectionType: String.self) { paths in
                TrackContextMenu(tracks: tracks.filter { paths.contains($0.path) }) {
                    play(tracks.firstIndex { paths.contains($0.path) })
                }
            } primaryAction: { paths in
                play(tracks.firstIndex { paths.contains($0.path) })
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if tracks.isEmpty {
                    ContentUnavailableView(smart.title, systemImage: smart.systemImage, description: Text(emptyText))
                }
            }
        }
        .navigationTitle(smart.title)
        .task(id: "\(smart.rawValue)-\(library.revision)-\(player.playsRecorded)-\(player.favoritesSaved)") {
            tracks = (try? await library.database.tracks(for: smart)) ?? []
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: smart.systemImage)
                .font(.system(size: 28))
                .foregroundStyle(theme.accent)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
            VStack(alignment: .leading, spacing: 3) {
                Text("SMART PLAYLIST")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(theme.accent)
                Text(smart.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("\(smart.subtitle) · \(tracks.count) songs, \(Format.minutes(tracks.map(\.duration).reduce(0, +)))")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            CircleButton(systemImage: "play.fill", help: "Play") { player.play(tracks) }
                .disabled(tracks.isEmpty)
            CircleButton(systemImage: "shuffle", help: "Shuffle") { player.playShuffled(tracks) }
                .disabled(tracks.isEmpty)
            Button("Save as Playlist") {
                Task { _ = await store.newPlaylist(with: tracks) }
            }
            .disabled(tracks.isEmpty)
            .help("Make an ordinary playlist with these songs as they are now")
        }
    }

    private var emptyText: String {
        switch smart {
        case .recentlyAdded: "Songs you add show up here."
        case .mostPlayed: "Songs you play show up here."
        case .topRated: "Heart songs to see them here."
        }
    }

    private func play(_ index: Int?) {
        guard let index else { return }
        player.play(tracks, startAt: index)
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
        app.isInStudio ? app.studioSourcePlaylistId == smart.playlistId
                       : app.selection == .playlists && app.selectedPlaylistId == smart.playlistId
    }
}
