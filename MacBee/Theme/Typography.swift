import SwiftUI

/// MacBee's text styles. Use these instead of hand-set sizes so every page reads the same.
extension Font {
    /// Album, playlist, movie, show and Now Playing titles.
    static let mbDetailTitle = Font.system(size: 34, weight: .bold)
    /// The title at the top of a page (Media, Artists, Albums…).
    static let mbPageTitle = Font.system(size: 30, weight: .bold)
    /// Section headings inside a page (Recently Played, Continue Watching…) and album titles on artist pages.
    static let mbSection = Font.system(size: 20, weight: .bold)
    /// Song names, list rows and buttons.
    static let mbRowTitle = Font.system(size: 13, weight: .medium)
    /// Body text and details under a title (artist, year, counts).
    static let mbSecondary = Font.system(size: 12)
    /// Small details: quality, times, captions.
    static let mbCaption = Font.system(size: 11)
    /// Small capitals labels (ALBUM, SMART PLAYLIST, STUDIOS). Use with `.mbLabelStyle()`.
    static let mbLabel = Font.system(size: 10, weight: .semibold)
}

extension View {
    /// The small capitals label style: 10 pt semibold, spaced out.
    func mbLabelStyle() -> some View {
        font(.mbLabel).tracking(0.8).textCase(.uppercase)
    }
}

/// Shared page spacing.
enum PageLayout {
    /// Left and right margin of every page.
    static let margin: CGFloat = 28
    static let top: CGFloat = 20
}
