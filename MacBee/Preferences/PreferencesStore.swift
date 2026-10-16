import Foundation
import Observation

/// App preferences (General, Appearance, Library, Plex, Tag Editor), saved between launches.
/// Audio output settings live in OutputSettingsStore; theme and accent in ThemeStore.
@MainActor
@Observable
final class PreferencesStore {
    var startPage: StartPage { didSet { save(startPage.rawValue, "startPage") } }
    /// The last page visited, for "Where I left off".
    var lastPage: SidebarItem { didSet { save(lastPage.rawValue, "lastPage") } }
    var checkLibraryAtLaunch: Bool { didSet { save(checkLibraryAtLaunch, "checkLibraryAtLaunch") } }
    var showQualityBadges: Bool { didSet { save(showQualityBadges, "showQualityBadges") } }
    var playCountRule: PlayCountRule { didSet { save(playCountRule.rawValue, "playCountRule") } }
    /// Sidebar width when expanded, in points.
    var sidebarWidth: Double { didSet { save(sidebarWidth, "sidebarWidth") } }
    var routineCheck: RoutineCheck { didSet { save(routineCheck.rawValue, "routineCheck") } }
    /// Play from the network drive, Plex, or automatically (drive at home, Plex when away).
    var playbackSource: PlaybackSourcePreference { didSet { save(playbackSource.rawValue, "playbackSource") } }
    /// The external tag editor app chosen in Preferences (Phase 8 opens songs in it).
    var tagEditorPath: String? { didSet { save(tagEditorPath, "tagEditorPath") } }

    static let sidebarWidthRange: ClosedRange<Double> = 170...280

    init() {
        let d = UserDefaults.standard
        startPage = d.string(forKey: "startPage").flatMap(StartPage.init) ?? .lastPage
        lastPage = d.string(forKey: "lastPage").flatMap(SidebarItem.init) ?? .albums
        checkLibraryAtLaunch = d.object(forKey: "checkLibraryAtLaunch") as? Bool ?? true
        showQualityBadges = d.object(forKey: "showQualityBadges") as? Bool ?? true
        playCountRule = d.string(forKey: "playCountRule").flatMap(PlayCountRule.init) ?? .halfOrFourMinutes
        sidebarWidth = d.object(forKey: "sidebarWidth") as? Double ?? 196
        routineCheck = (d.object(forKey: "routineCheck") as? Int).flatMap(RoutineCheck.init) ?? .every30
        playbackSource = d.string(forKey: "playbackSource").flatMap(PlaybackSourcePreference.init) ?? .automatic
        // Default to TagBee when nothing valid is chosen yet (e.g. on a new Mac).
        let savedEditor = d.string(forKey: "tagEditorPath")
        if let savedEditor, FileManager.default.fileExists(atPath: savedEditor + "/Contents/Info.plist") {
            tagEditorPath = savedEditor
        } else {
            let tagBee = "/Applications/TagBee.app"
            tagEditorPath = FileManager.default.fileExists(atPath: tagBee) ? tagBee : nil
        }
    }

    /// The page to show at launch.
    var launchPage: SidebarItem {
        switch startPage {
        case .home: .home
        case .artists: .artists
        case .albums: .albums
        case .lastPage: lastPage
        }
    }

    private func save(_ value: Any?, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
