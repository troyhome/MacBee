import AppKit
import MacBeeAudio
import MacBeeLibrary
import Observation

/// Creates and owns the app's long-lived objects: library, playback engine, queue, theme.
@MainActor
@Observable
final class AppModel {
    /// Nil only if the library database couldn't be opened (see `libraryError`).
    let library: MusicLibrary?
    let libraryError: String?
    let player: PlayerViewModel
    /// Nil only when the library couldn't be opened.
    let playlists: PlaylistStore?
    /// Opens songs in TagBee (or another chosen tag editor) and re-reads them after saving.
    let tagEditor: ExternalTagEditor?
    /// Plex sign-in and the away-from-home route to the same songs.
    let plex: PlexConnection?
    let themeStore = ThemeStore()
    let preferences: PreferencesStore

    /// Where you are now. Every change remembers the previous place for the back arrow.
    private(set) var location: Location {
        didSet {
            if !isGoingBack, oldValue != location {
                backStack.append(oldValue)
                if backStack.count > 100 { backStack.removeFirst() }
            }
            canGoBack = !backStack.isEmpty
            if location.page != .search { preferences.lastPage = location.page }
        }
    }
    @ObservationIgnored private var backStack: [Location] = []
    @ObservationIgnored private var isGoingBack = false
    /// Mirrors `backStack.isEmpty` so views can show or hide the back arrow.
    private(set) var canGoBack = false

    /// The sidebar page. Choosing a different page closes any open album or playlist.
    var selection: SidebarItem {
        get { location.page }
        set { if newValue != location.page { go(to: newValue) } }
    }
    /// The playlist open on the Playlists page (nil shows all playlists).
    var selectedPlaylistId: Int64? {
        get { location.playlistId }
        set { location = Location(page: location.page, playlistId: newValue) }
    }
    /// Playlist Studio is open. In studio mode, clicking a playlist in the sidebar shows its songs in the studio.
    var isInStudio: Bool { location.page == .playlistStudio }
    /// The playlist whose songs the studio's middle pane shows (nil = the whole library).
    var studioSourcePlaylistId: Int64?
    /// Where you were before entering the studio; clicking Playlist Studio again returns there.
    @ObservationIgnored private var locationBeforeStudio: Location?

    /// Album pages opened on top of the current page.
    var albumPath: [AlbumSummary] {
        get { location.albums }
        set { location.albums = newValue }
    }
    /// Text in the sidebar search field.
    var searchText = ""
    /// The queue drawer on the right of the window.
    var showQueue = false
    /// The full-window Now Playing view.
    var showNowPlaying = false
    /// Bumped by ⌘F; the sidebar focuses the search field when it changes.
    private(set) var searchFocusRequest = 0

    @ObservationIgnored private let engine: SFBPlaybackEngine
    @ObservationIgnored private let queue = QueueManager()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var nowPlaying: NowPlayingService?

    init() {
        var library: MusicLibrary?
        var libraryError: String?
        do {
            library = try MusicLibrary()
        } catch {
            libraryError = error.localizedDescription
        }
        self.library = library
        self.libraryError = libraryError
        playlists = library.map { PlaylistStore(library: $0) }
        let preferences = PreferencesStore()
        self.preferences = preferences
        location = Location(page: preferences.launchPage)
        tagEditor = library.map { ExternalTagEditor(library: $0, preferences: preferences) }

        engine = SFBPlaybackEngine(settings: OutputSettingsStore.load())
        engine.queueSource = queue
        let plex = library.map { PlexConnection(library: $0) }
        self.plex = plex
        player = PlayerViewModel(engine: engine, queue: queue, database: library?.database, preferences: preferences,
                                 router: PlaybackRouter(plex: plex, preferences: preferences))
        nowPlaying = NowPlayingService(player: player, library: library)

        // Stop playback and give up exclusive access when the app quits.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [engine] _ in
            MainActor.assumeIsolated { engine.shutdown() }
        }
    }

    // MARK: - Navigation

    /// Shows a page from its start (closing any open album or playlist).
    func go(to page: SidebarItem) {
        if page == .playlistStudio && !isInStudio { locationBeforeStudio = location }
        location = Location(page: page)
    }

    /// The Playlist Studio button: enters studio mode, or leaves it back to where you were.
    func toggleStudio() {
        if isInStudio {
            location = locationBeforeStudio ?? Location(page: .home)
            locationBeforeStudio = nil
        } else {
            go(to: .playlistStudio)
        }
    }

    /// A playlist clicked in the sidebar: in the studio it becomes the song source; elsewhere its page opens.
    func selectPlaylistInSidebar(_ id: Int64) {
        if isInStudio {
            studioSourcePlaylistId = id
        } else {
            openPlaylist(id)
        }
    }

    /// Shows a playlist on the Playlists page.
    func openPlaylist(_ id: Int64) {
        location = Location(page: .playlists, playlistId: id)
    }

    /// Opens an album page on top of the current page.
    func openAlbum(_ album: AlbumSummary) {
        location.albums.append(album)
    }

    /// Opens the album of the song that's playing, on the Albums page.
    func showCurrentAlbum() async {
        guard let track = player.currentTrack, let database = library?.database,
              let album = try? await database.album(key: track.albumKey) else { return }
        location = Location(page: .albums, albums: [album])
    }

    /// Returns to the previous place, wherever it was.
    func goBack() {
        guard let previous = backStack.popLast() else { return }
        isGoingBack = true
        location = previous
        isGoingBack = false
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    /// Loads the library and starts watching folders. Safe to call more than once.
    func start() async {
        guard !started else { return }
        started = true
        library?.periodicCheckInterval = preferences.routineCheck.interval
        await library?.start(checkForChanges: preferences.checkLibraryAtLaunch)
    }
}
