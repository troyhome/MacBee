import Foundation
import SwiftUI
import Observation

/// The chosen theme and accent, saved between launches. Edited in Preferences > Appearance.
@MainActor
@Observable
final class ThemeStore {
    var kind: ThemeKind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: "themeKind") }
    }
    var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "themeAccent") }
    }
    /// The color picked when `accent` is `.custom`, as 0xRRGGBB.
    var customAccentHex: UInt32 {
        didSet { UserDefaults.standard.set(Int(customAccentHex), forKey: "themeCustomAccent") }
    }

    /// macOS is in dark mode (used by the System theme).
    private(set) var systemIsDark = ThemeStore.readSystemIsDark()

    var accentColor: Color { accent == .custom ? Color(hex: customAccentHex) : accent.color }
    /// The theme actually in use, with System resolved to Dark or Light.
    var theme: Theme {
        let resolved: ThemeKind = kind == .system ? (systemIsDark ? .dark : .light) : kind
        return .make(resolved, accent: accentColor)
    }

    @ObservationIgnored private var appearanceObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        kind = defaults.string(forKey: "themeKind").flatMap(ThemeKind.init) ?? .system
        accent = defaults.string(forKey: "themeAccent").flatMap(AccentChoice.init) ?? .cyan
        customAccentHex = (defaults.object(forKey: "themeCustomAccent") as? Int).map { UInt32($0) } ?? 0x33D6E0
        // macOS announces dark/light mode switches (including automatic ones at sunset).
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemIsDark = ThemeStore.readSystemIsDark() }
        }
    }

    private static func readSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
