import AppKit
import SwiftUI

/// Color tokens. Views read these instead of hard-coding colors, so the theme
/// (Light / Medium Gray / Dark) and accent color can be switched in Preferences (Phase 6).
struct Theme {
    var kind: ThemeKind
    var accent: Color
    /// Text and icons drawn on top of the accent color.
    var onAccent: Color
    /// Main content area.
    var background: Color
    var sidebar: Color
    /// Bottom play bar.
    var bar: Color
    /// Placeholders, hovered rows.
    var surface: Color
    /// Selected items.
    var elevated: Color
    var separator: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    /// Bit-perfect badge.
    var good: Color
    /// Not-bit-perfect badge.
    var warning: Color

    var colorScheme: ColorScheme { kind == .light ? .light : .dark }

    static func make(_ kind: ThemeKind, accent: Color = AccentChoice.cyan.color) -> Theme {
        let onAccent = accent.isLight ? Color.black : Color.white
        switch kind {
        case .dark, .system: // ThemeStore resolves .system before calling this
            return Theme(kind: kind, accent: accent, onAccent: onAccent,
                         background: Color(hex: 0x0E0E10), sidebar: Color(hex: 0x09090B), bar: Color(hex: 0x141417),
                         surface: Color(hex: 0x1C1C20), elevated: Color(hex: 0x26262B),
                         separator: .white.opacity(0.07),
                         textPrimary: .white, textSecondary: .white.opacity(0.62), textTertiary: .white.opacity(0.38),
                         good: Color(hex: 0x3DDC84), warning: Color(hex: 0xFFB340))
        case .mediumGray:
            return Theme(kind: kind, accent: accent, onAccent: onAccent,
                         background: Color(hex: 0x2B2B2F), sidebar: Color(hex: 0x232327), bar: Color(hex: 0x323237),
                         surface: Color(hex: 0x38383E), elevated: Color(hex: 0x44444B),
                         separator: .white.opacity(0.08),
                         textPrimary: .white, textSecondary: .white.opacity(0.66), textTertiary: .white.opacity(0.42),
                         good: Color(hex: 0x3DDC84), warning: Color(hex: 0xFFB340))
        case .light:
            return Theme(kind: kind, accent: accent, onAccent: onAccent,
                         background: Color(hex: 0xF7F7F8), sidebar: Color(hex: 0xEDEDF0), bar: .white,
                         surface: Color(hex: 0xE9E9EC), elevated: Color(hex: 0xDEDEE3),
                         separator: .black.opacity(0.08),
                         textPrimary: .black.opacity(0.88), textSecondary: .black.opacity(0.58), textTertiary: .black.opacity(0.38),
                         good: Color(hex: 0x1E9E5A), warning: Color(hex: 0xC77700))
        }
    }
}

enum ThemeKind: String, CaseIterable, Identifiable {
    /// Follows macOS: Dark in dark mode, Light in light mode.
    case system, dark, mediumGray, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .mediumGray: "Medium Gray"
        case .light: "Light"
        }
    }
}

/// Preset accent colors; `custom` uses the color picked in Preferences.
enum AccentChoice: String, CaseIterable, Identifiable {
    case cyan, violet, orange, green, pink, custom
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .cyan: Color(hex: 0x33D6E0)
        case .violet: Color(hex: 0x9B7BFF)
        case .orange: Color(hex: 0xFF8A3D)
        case .green: Color(hex: 0x3DDC84)
        case .pink: Color(hex: 0xFF5C93)
        case .custom: Color(hex: 0x33D6E0)
        }
    }
}

extension Color {
    /// True for bright colors, where black text reads better than white.
    var isLight: Bool {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return true }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.55
    }

    /// 0xRRGGBB, for saving a picked color.
    var hexValue: UInt32 {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return 0x33D6E0 }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .make(.dark)
}
