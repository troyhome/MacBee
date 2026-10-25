import Foundation
import MacBeeLibrary
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
    /// Look up lyrics online for songs without any, and save them next to the song.
    var findLyricsOnline: Bool { didSet { save(findLyricsOnline, "findLyricsOnline") } }
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
    /// The Music page's sections in the order shown (hidden ones are left out of `homeHidden`).
    var homeOrder: [HomeSectionKind] { didSet { save(homeOrder.map(\.rawValue), "homeOrder") } }
    var homeHidden: Set<HomeSectionKind> { didSet { save(homeHidden.map(\.rawValue), "homeHidden") } }
    /// Folders (or whole drives) with movies and TV shows, for the Videos page.
    var videoFolders: [String] { didSet { save(videoFolders, "videoFolders") } }
    /// Video folders switched off: kept in the list, but their movies and shows are left out.
    var pausedVideoFolders: [String] { didSet { save(pausedVideoFolders, "pausedVideoFolders") } }
    /// The video folders that are switched on.
    var activeVideoFolders: [String] { videoFolders.filter { !pausedVideoFolders.contains($0) } }
    /// Which drive each video folder is on: path -> [volumeID, path on the drive] (see `VolumeLocation`).
    var videoFolderVolumes: [String: [String]] { didSet { save(videoFolderVolumes, "videoFolderVolumes") } }
    /// When a song, album or playlist ends, keep going with a mix made from the last song.
    var continuousPlay: Bool { didSet { save(continuousPlay, "continuousPlay") } }
    /// TV shows: the next episode starts when one ends.
    var continuousPlayEpisodes: Bool { didSet { save(continuousPlayEpisodes, "continuousPlayEpisodes") } }
    /// Also save hearts in the song files (FLAC and Ogg), so they travel with the files.
    var saveFavoritesInFiles: Bool { didSet { save(saveFavoritesInFiles, "saveFavoritesInFiles") } }

    static let sidebarWidthRange: ClosedRange<Double> = 170...280

    init() {
        let d = UserDefaults.standard
        startPage = d.string(forKey: "startPage").flatMap(StartPage.init) ?? .lastPage
        lastPage = d.string(forKey: "lastPage").flatMap(SidebarItem.init) ?? .albums
        checkLibraryAtLaunch = d.object(forKey: "checkLibraryAtLaunch") as? Bool ?? true
        showQualityBadges = d.object(forKey: "showQualityBadges") as? Bool ?? true
        findLyricsOnline = d.object(forKey: "findLyricsOnline") as? Bool ?? true
        playCountRule = d.string(forKey: "playCountRule").flatMap(PlayCountRule.init) ?? .halfOrFourMinutes
        sidebarWidth = d.object(forKey: "sidebarWidth") as? Double ?? 196
        routineCheck = (d.object(forKey: "routineCheck") as? Int).flatMap(RoutineCheck.init) ?? .every30
        playbackSource = d.string(forKey: "playbackSource").flatMap(PlaybackSourcePreference.init) ?? .automatic
        tagEditorPath = d.string(forKey: "tagEditorPath")
        let savedOrder = (d.stringArray(forKey: "homeOrder") ?? []).compactMap(HomeSectionKind.init)
        // Sections added in later versions go at the end.
        homeOrder = savedOrder + HomeSectionKind.allCases.filter { !savedOrder.contains($0) }
        homeHidden = Set((d.stringArray(forKey: "homeHidden") ?? []).compactMap(HomeSectionKind.init))
        hideCompilationOnlyArtists = d.object(forKey: "hideCompilationOnlyArtists") as? Bool ?? false
        videoFolders = d.stringArray(forKey: "videoFolders") ?? []
        pausedVideoFolders = d.stringArray(forKey: "pausedVideoFolders") ?? []
        videoFolderVolumes = d.dictionary(forKey: "videoFolderVolumes") as? [String: [String]] ?? [:]
        continuousPlay = d.object(forKey: "continuousPlay") as? Bool ?? true
        continuousPlayEpisodes = d.object(forKey: "continuousPlayEpisodes") as? Bool ?? true
        saveFavoritesInFiles = d.object(forKey: "saveFavoritesInFiles") as? Bool ?? true
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
        if let location = VolumeLocation.identify(path) {
            videoFolderVolumes[path] = [location.volumeID, location.pathInVolume]
        }
    }

    /// The video folder is there and on its own drive (not an empty leftover in /Volumes).
    func isVideoFolderConnected(_ path: String) -> Bool {
        VolumeLocation.isConnected(path, volumeID: videoFolderVolumes[path]?.first)
    }

    /// Video folders on drives: learns which drive each is on, and follows a drive now mounted somewhere else.
    /// Returns the folders that moved (old path, new path).
    func locateVideoFolders() -> [(from: String, to: String)] {
        var moved: [(from: String, to: String)] = []
        for path in videoFolders {
            if isVideoFolderConnected(path) {
                if videoFolderVolumes[path] == nil, let location = VolumeLocation.identify(path) {
                    videoFolderVolumes[path] = [location.volumeID, location.pathInVolume]
                }
                continue
            }
            let saved = videoFolderVolumes[path]
            let newPath = saved.flatMap { $0.count == 2 ? VolumeLocation.currentPath(volumeID: $0[0], pathInVolume: $0[1]) : nil }
                ?? (saved == nil ? VolumeLocation.renumberedMountPath(of: path) : nil)
            guard let newPath, newPath != path, !videoFolders.contains(newPath) else { continue }
            videoFolders = videoFolders.map { $0 == path ? newPath : $0 }
            pausedVideoFolders = pausedVideoFolders.map { $0 == path ? newPath : $0 }
            videoFolderVolumes[newPath] = saved ?? VolumeLocation.identify(newPath).map { [$0.volumeID, $0.pathInVolume] }
            videoFolderVolumes[path] = nil
            moved.append((path, newPath))
        }
        return moved
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
