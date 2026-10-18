import MacBeeLibrary
import SwiftUI

/// Left column of the Artists page. Click selects, double-click (or Return) plays everything,
/// arrow keys move the selection.
struct ArtistListColumn: View {
    let artists: [ArtistSummary]
    @Binding var selectedKey: String

    @Environment(PlayerViewModel.self) private var player
    @FocusState private var focused: Bool
    @State private var didScrollToSelection = false

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(artists) { artist in
                            ArtistRow(artist: artist, isSelected: artist.artistKey == selectedKey)
                                .id(artist.artistKey)
                                .onTapGesture(count: 2) { Task { await player.playArtist(artist) } }
                                .onTapGesture {
                                    selectedKey = artist.artistKey
                                    focused = true
                                }
                                .contextMenu { ArtistContextMenu(artist: artist) }
                                .draggable(DragPayload.artist(artist.artistKey).string)
                        }
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity)
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { move(by: -1, proxy) }
                .onKeyPress(.downArrow) { move(by: 1, proxy) }
                .onKeyPress(.return) {
                    guard let artist = artists.first(where: { $0.artistKey == selectedKey }) else { return .ignored }
                    Task { await player.playArtist(artist) }
                    return .handled
                }
                // The A–Z strip sits beside the list, clear of its scroll bar.
                AlphabetIndex(available: Set(artists.map { AlphabetIndex.letter(for: $0.name) })) { letter in
                    if let first = artists.first(where: { AlphabetIndex.letter(for: $0.name) == letter }) {
                        proxy.scrollTo(first.artistKey, anchor: .top)
                    }
                }
                .padding(.horizontal, 3)
            }
            .onChange(of: artists) {
                // Show the remembered artist when the list first loads.
                guard !didScrollToSelection, !artists.isEmpty else { return }
                didScrollToSelection = true
                proxy.scrollTo(selectedKey, anchor: .center)
            }
        }
    }

    private func move(by delta: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !artists.isEmpty else { return .ignored }
        let current = artists.firstIndex { $0.artistKey == selectedKey } ?? 0
        let next = min(max(current + delta, 0), artists.count - 1)
        selectedKey = artists[next].artistKey
        proxy.scrollTo(selectedKey)
        return .handled
    }
}

private struct ArtistRow: View {
    let artist: ArtistSummary
    let isSelected: Bool
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artworkId: artist.artworkId, pixelSize: 120, cornerRadius: 22)
                .frame(width: 44, height: 44)
            Text(artist.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? theme.onAccent : theme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? theme.accent : (hovering ? theme.surface : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums") · \(artist.trackCount) songs")
    }
}
