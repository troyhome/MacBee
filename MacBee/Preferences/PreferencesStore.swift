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
    /// Artists who only appear on compilations are left out of the Artists page.
    var hideCompilationOnlyArtists: Bool { didSet { save(hideCompilationOnlyArtists, "hideCompilationOnlyArtists") } }
    /// Folders (or whole drives) with movies and TV shows, for the Videos page.
    var videoFolders: [String] { didSet { save(videoFolders, "videoFolders") } }
    /// The keyboard's media keys control MacBee whenever it has music loaded, even with other players open.
    var mediaKeysAlwaysMacBee: Bool { didSet { save(mediaKeysAlwaysMacBee, "mediaKeysAlwaysMacBee") } }

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
        tagEditorPath = d.string(forKey: "tagEditorPath")
        hideCompilationOnlyArtists = d.object(forKey: "hideCompilationOnlyArtists") as? Bool ?? false
        videoFolders = d.stringArray(forKey: "videoFolders") ?? []
        mediaKeysAlwaysMacBee = d.object(forKey: "mediaKeysAlwaysMacBee") as? Bool ?? true
        useDefaultTagEditorIfNeeded()
    }

    /// Picks TagBee when no valid tag editor is chosen (e.g. on a new Mac, or TagBee was installed
    /// after MacBee opened). Called at launch and whenever MacBee comes back to the front.
    func useDefaultTagEditorIfNeeded() {
        if let tagEditorPath, FileManager.default.fileExists(atPath: tagEditorPath + "/Contents/Info.plist") { return }
        let tagBee = "/Applications/TagBee.app"
        let found = FileManager.default.fileExists(atPath: tagBee) ? tagBee : nil
        if found != tagEditorPath { tagEditorPath = found }
    }

    func addVideoFolder(_ path: String) {
        if !videoFolders.contains(path) { videoFolders.append(path) }
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
