import AppKit
import MacBeeLibrary
import SwiftUI

/// Title, artist, quality badge and album in the play bar. Clicking opens the album, at this song.
/// If any line is cut off, hovering opens a panel above it with the full text.
struct TrackInfoText: View {
    let track: Track

    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @State private var hovering = false
    @State private var showFull = false
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        lines(fullText: false)
            .lineLimit(1)
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { availableWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in availableWidth = width }
            })
            .overlay(alignment: .bottomLeading) {
                if showFull {
                    lines(fullText: true)
                        .frame(width: 320, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .background(
                            // 80% opaque, with a blur behind so text underneath can't be read through it.
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.elevated.opacity(0.8))
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.separator, lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                        .offset(x: -10, y: 10)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onHover { isHovering in
                hovering = isHovering
                if isHovering {
                    // Short pause so the panel doesn't pop up when the mouse just passes by.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        if hovering && isTruncated { withAnimation(.easeOut(duration: 0.15)) { showFull = true } }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { showFull = false }
                }
            }
            .onChange(of: track.path) { showFull = false }
            .contentShape(Rectangle())
            .onTapGesture {
                showFull = false
                app.showNowPlaying = false
                Task { await app.showCurrentAlbum() }
            }
            .help("Show this album")
    }

    private func lines(fullText: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(track.displayArtist)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                QualityBadge(track: track)
                Text(track.displayAlbum)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .lineLimit(fullText ? nil : 1)
    }

    /// True when any line is wider than the space it has.
    private var isTruncated: Bool {
        guard availableWidth > 0 else { return false }
        func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
        }
        let badge = width(track.formatSummary + " HI-RES  ", 9, .semibold) + 10 + 6
        return width(track.displayTitle, 13, .semibold) > availableWidth
            || width(track.displayArtist, 12) > availableWidth
            || badge + width(track.displayAlbum, 11) > availableWidth
    }
}
