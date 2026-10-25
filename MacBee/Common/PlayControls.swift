import MacBeeLibrary
import SwiftUI

/// The main Play button: an accent capsule. Always first in a row of play controls.
struct PlayButton: View {
    var title = "Play"
    var large = true
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(.system(size: large ? 14 : 13, weight: .semibold))
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, large ? 22 : 18)
                .frame(height: large ? 40 : 34)
                .background(Capsule().fill(theme.accent.opacity(hovering ? 0.85 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
    }
}

/// Round "…" button that opens a menu.
struct MoreMenuButton<Content: View>: View {
    var help = "More"
    var diameter: CGFloat = 40
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(hovering ? theme.elevated : theme.surface))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The heart for a group of songs (an album, an artist's album). Filled when every song is a favorite.
struct FavoriteTracksButton: View {
    let tracks: [Track]
    var diameter: CGFloat = 40
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        CircleButton(systemImage: isFavorite ? "heart.fill" : "heart",
                     help: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                     tinted: isFavorite, diameter: diameter) {
            player.setFavorite(tracks, !isFavorite)
        }
        .disabled(tracks.isEmpty)
    }

    private var isFavorite: Bool { !tracks.isEmpty && tracks.allSatisfy(player.isFavorite) }
}

/// Play, Shuffle, a heart (when `favoriteTracks` is given) and a "…" menu, in that order on every page.
struct PlayControls<More: View>: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void
    var favoriteTracks: [Track]?
    var large = true
    var moreHelp = "More"
    @ViewBuilder let more: () -> More

    var body: some View {
        HStack(spacing: 10) {
            PlayButton(large: large, action: onPlay)
            CircleButton(systemImage: "shuffle", help: "Shuffle", tinted: false, diameter: diameter, action: onShuffle)
            if let favoriteTracks { FavoriteTracksButton(tracks: favoriteTracks, diameter: diameter) }
            MoreMenuButton(help: moreHelp, diameter: diameter, content: more)
        }
    }

    private var diameter: CGFloat { large ? 40 : 34 }
}

extension PlayControls where More == EmptyView {
    init(onPlay: @escaping () -> Void, onShuffle: @escaping () -> Void, favoriteTracks: [Track]? = nil, large: Bool = true) {
        self.init(onPlay: onPlay, onShuffle: onShuffle, favoriteTracks: favoriteTracks, large: large) { EmptyView() }
    }
}

/// The header at the top of every page: back button, title with an optional line under it, then the page's
/// controls on the right (play controls, layout and sort, search; the search field gives up room first).
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showsDivider = false
    @ViewBuilder let trailing: () -> Trailing

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            if app.canGoBack {
                CircleButton(systemImage: "chevron.left", help: "Back", tinted: false, diameter: 32) { app.goBack() }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.mbPageTitle)
                    .foregroundStyle(theme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.mbSecondary)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, PageLayout.margin)
        .padding(.top, PageLayout.top)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(theme.separator).frame(height: 1).padding(.horizontal, PageLayout.margin)
            }
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showsDivider: Bool = false) {
        self.init(title: title, subtitle: subtitle, showsDivider: showsDivider) { EmptyView() }
    }
}

/// A thin divider between groups of header controls.
struct HeaderDivider: View {
    @Environment(\.theme) private var theme
    var body: some View { Rectangle().fill(theme.separator).frame(width: 1, height: 22) }
}

/// The top of an album or playlist page: back button, big artwork, a small label (ALBUM, PLAYLIST), the title,
/// a line of details and the play controls, over a soft blur of the artwork.
struct DetailHero<Art: View, Subtitle: View, Controls: View, Backdrop: View>: View {
    let label: String
    let title: String
    @ViewBuilder let art: () -> Art
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let backdrop: () -> Backdrop

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if app.canGoBack {
                CircleButton(systemImage: "chevron.left", help: "Back", tinted: false, diameter: 32) { app.goBack() }
            }
            HStack(alignment: .bottom, spacing: 28) {
                art()
                    .frame(width: 220, height: 220)
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                VStack(alignment: .leading, spacing: 8) {
                    Text(label)
                        .mbLabelStyle()
                        .foregroundStyle(theme.textSecondary)
                    Text(title)
                        .font(.mbDetailTitle)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                    subtitle()
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                    controls()
                        .padding(.top, 10)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background {
            backdrop()
                .blur(radius: 50)
                .saturation(1.2)
                .overlay(theme.background.opacity(0.4))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
