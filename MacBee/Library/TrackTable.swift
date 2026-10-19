import MacBeeLibrary
import SwiftUI

/// A table of songs like TIDAL's Tracks page: #, Title (with cover), Artist, Album, Date Added and Time
/// columns (click a column name to sort, again to reverse), and + (add to playlist) and a heart on every row.
/// Double-click or Return plays; right-click for the usual song menu; drag songs onto playlists.
struct TrackTable: View {
    let tracks: [Track]
    @Binding var sort: TrackTableSort
    /// The date shown in the Date Added column.
    let dateAdded: (Track) -> Date
    let play: (Int) -> Void

    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme
    @State private var selection = Set<String>()

    var body: some View {
        GeometryReader { geometry in
            let columns = TrackTableColumns(width: geometry.size.width)
            List(selection: $selection) {
                Section {
                    ForEach(Array(tracks.enumerated()), id: \.element.path) { index, track in
                        TrackTableRow(track: track, number: index + 1, columns: columns, added: dateAdded(track),
                                      isCurrent: player.currentTrack?.path == track.path, isPlaying: player.isPlaying,
                                      isFavorite: player.isFavorite(track))
                            .tag(track.path)
                            .draggable(DragPayload.tracks(selectedIds(including: track)).string)
                    }
                } header: {
                    TrackTableHeader(columns: columns, sort: $sort)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: String.self) { paths in
                TrackContextMenu(tracks: tracks.filter { paths.contains($0.path) }) {
                    playFirst(of: paths)
                }
            } primaryAction: { paths in
                playFirst(of: paths)
            }
        }
    }

    /// Dragging a selected row drags every selected song; dragging another row drags just that one.
    private func selectedIds(including track: Track) -> [Int64] {
        guard selection.contains(track.path) else { return [track.id].compactMap { $0 } }
        return tracks.filter { selection.contains($0.path) }.compactMap(\.id)
    }

    private func playFirst(of paths: Set<String>) {
        if let index = tracks.firstIndex(where: { paths.contains($0.path) }) { play(index) }
    }
}

/// Which column the table is sorted by. `nil` keeps the page's own order (newest first for Favorites).
struct TrackTableSort: Equatable {
    enum Column { case title, artist, album, added, time }

    var column: Column?
    var ascending = true

    /// Clicking a column sorts by it; clicking it again reverses; a third click goes back to the page's order.
    mutating func toggle(_ clicked: Column) {
        if column != clicked {
            column = clicked
            ascending = clicked != .added // newest first is the natural way to read dates
        } else if ascending == (clicked != .added) {
            ascending.toggle()
        } else {
            column = nil
        }
    }

    func apply(to tracks: [Track], added: (Track) -> Date) -> [Track] {
        guard let column else { return tracks }
        let sorted: [Track]
        switch column {
        case .title: sorted = tracks.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .artist: sorted = tracks.sorted { $0.displayArtist.localizedStandardCompare($1.displayArtist) == .orderedAscending }
        case .album: sorted = tracks.sorted { $0.displayAlbum.localizedStandardCompare($1.displayAlbum) == .orderedAscending }
        case .added: sorted = tracks.sorted { added($0) < added($1) }
        case .time: sorted = tracks.sorted { $0.duration < $1.duration }
        }
        return ascending ? sorted : sorted.reversed()
    }
}

/// Column widths, shared by the header and every row so they line up.
struct TrackTableColumns {
    static let number: CGFloat = 30
    static let cover: CGFloat = 40
    static let added: CGFloat = 110
    static let time: CGFloat = 54
    static let actions: CGFloat = 64
    static let spacing: CGFloat = 14

    let title: CGFloat
    let artist: CGFloat
    let album: CGFloat
    let showsAlbum: Bool
    let showsAdded: Bool

    init(width: CGFloat) {
        // Narrow windows drop Date Added, then Album.
        showsAdded = width > 760
        showsAlbum = width > 560
        var fixed = Self.number + Self.cover + Self.time + Self.actions + Self.spacing * 5 + 40 // + List insets
        if showsAdded { fixed += Self.added + Self.spacing }
        if showsAlbum { fixed += Self.spacing }
        let flexible = max(width - fixed, 240)
        title = flexible * (showsAlbum ? 0.42 : 0.6)
        artist = flexible * (showsAlbum ? 0.29 : 0.4)
        album = showsAlbum ? flexible * 0.29 : 0
    }
}

private struct TrackTableHeader: View {
    let columns: TrackTableColumns
    @Binding var sort: TrackTableSort
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: TrackTableColumns.spacing) {
            Text("#")
                .frame(width: TrackTableColumns.number, alignment: .trailing)
            heading("TITLE", .title)
                .frame(width: TrackTableColumns.cover + TrackTableColumns.spacing + columns.title, alignment: .leading)
            heading("ARTIST", .artist)
                .frame(width: columns.artist, alignment: .leading)
            if columns.showsAlbum {
                heading("ALBUM", .album)
                    .frame(width: columns.album, alignment: .leading)
            }
            if columns.showsAdded {
                heading("DATE ADDED", .added)
                    .frame(width: TrackTableColumns.added, alignment: .leading)
            }
            heading("TIME", .time)
                .frame(width: TrackTableColumns.time, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(theme.textSecondary)
        .padding(.vertical, 8)
        .background(theme.background)
    }

    private func heading(_ title: String, _ column: TrackTableSort.Column) -> some View {
        Button {
            sort.toggle(column)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if sort.column == column {
                    Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title.capitalized)")
    }
}

private struct TrackTableRow: View {
    let track: Track
    let number: Int
    let columns: TrackTableColumns
    let added: Date
    let isCurrent: Bool
    let isPlaying: Bool
    let isFavorite: Bool

    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: TrackTableColumns.spacing) {
            Group {
                if isCurrent {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(theme.accent)
                } else {
                    Text("\(number)")
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .font(.system(size: 12).monospacedDigit())
            .frame(width: TrackTableColumns.number, alignment: .trailing)

            ArtworkView(artworkId: track.artworkId, pixelSize: 96, cornerRadius: 4)
                .frame(width: TrackTableColumns.cover, height: TrackTableColumns.cover)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isCurrent ? theme.accent : theme.textPrimary)
                if preferences.showQualityBadges {
                    Text(track.formatSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .lineLimit(1)
            .frame(width: columns.title, alignment: .leading)

            LinkText(text: track.displayArtist) { app.openArtist(key: track.artistKey) }
                .frame(width: columns.artist, alignment: .leading)
                .help("Show \(track.displayArtist)")

            if columns.showsAlbum {
                LinkText(text: track.displayAlbum) { Task { await app.openAlbum(key: track.albumKey) } }
                    .frame(width: columns.album, alignment: .leading)
                    .help("Open \(track.displayAlbum)")
            }

            if columns.showsAdded {
                Text(TrackTableDate.text(for: added))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: TrackTableColumns.added, alignment: .leading)
                    .help(added.formatted(date: .long, time: .shortened))
            }

            Text(Format.time(track.duration))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .frame(width: TrackTableColumns.time, alignment: .leading)

            HStack(spacing: 14) {
                Menu {
                    AddToPlaylistItems { [track] }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(theme.textSecondary)
                .help("Add to Playlist")

                Button {
                    player.setFavorite([track], !isFavorite)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundStyle(isFavorite ? theme.accent : theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            .frame(width: TrackTableColumns.actions, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Artist and album names: click to open, underlined while the mouse is over them.
private struct LinkText: View {
    let text: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(hovering ? theme.textPrimary : theme.textSecondary)
                .underline(hovering)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "Today", "Yesterday", "3 days ago", "Last week", "Last month", or a date, like TIDAL.
enum TrackTableDate {
    static func text(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<14: return "Last week"
        case 14..<30: return "\(days / 7) weeks ago"
        case 30..<60: return "Last month"
        default: return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}
