import AppKit
import MacBeeAudio
import MacBeeLibrary
import MacBeeVideo
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
    /// Keeps plays, favorites and playlists in step with MacBee on Troy's other Mac.
    let networkSync: NetworkSync?
    /// Plex sign-in and the away-from-home route to the same songs.
    let plex: PlexConnection?
    let themeStore = ThemeStore()
    /// The 16-band equalizer (off by default).
    let equalizer: EqualizerStore
    /// Movies, shows and music videos.
    let videos = VideoLibrary()
    /// Lyrics looked up online for songs without any.
    let lyrics = LyricsService()
    /// Copy To's scan and copy, which keep going while you browse.
    let copyTo = CopyToRunner()
    /// The video being watched, if any.
    private(set) var videoSession: VideoSession?
    /// The video is in the mini player window instead of over the main window.
    private(set) var videoIsMini = false
    @ObservationIgnored private let videoMiniWindow = VideoMiniWindow()
    var playingVideo: VideoPlayback? { videoSession?.current }
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
    /// Track Studio is open: a mode like Playlist Studio. A playlist clicked in the sidebar feeds its song list.
    var isInTrackStudio: Bool { location.page == .tags }
    /// A library page shown beside Track Studio (Albums, Artists, Collections, Music, Search) while in the mode.
    var trackStudioBrowse: SidebarItem?
    /// The playlist (or smart playlist) whose songs Track Studio lists (nil = search the library).
    var trackStudioSourcePlaylistId: Int64?
    /// Where you were before entering Track Studio; clicking it again returns there.
    @ObservationIgnored private var locationBeforeTrackStudio: Location?

    /// Album pages opened on top of the current page.
    var albumPath: [AlbumSummary] {
        get { location.albums }
        set { location.albums = newValue }
    }
    /// The page the current music was started from, for "Playing From" in the sidebar.
    private(set) var playingFrom: Location?
    /// Text in the sidebar search field.
    var searchText = ""
    /// The queue drawer on the right of the window.
    var showQueue = false {
        didSet { if showQueue { showLyrics = false } }
    }
    /// The lyrics drawer on the right of the window (shares the place with the queue).
    var showLyrics = false {
        didSet { if showLyrics { showQueue = false } }
    }
    /// The full-window Now Playing view.
    var showNowPlaying = false
    /// Bumped by ⌘F; the sidebar focuses the search field when it changes.
    private(set) var searchFocusRequest = 0

    @ObservationIgnored private let engine: SFBPlaybackEngine
    @ObservationIgnored private let queue = QueueManager()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var nowPlaying: NowPlayingService?
    /// Catches the media keys so other players (Qobuz, Spotify) don't get them.
    let mediaKeys: MediaKeyTap

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
        let networkSync = library.map { NetworkSync(library: $0) }
        self.networkSync = networkSync

        engine = SFBPlaybackEngine(settings: OutputSettingsStore.load())
        engine.queueSource = queue
        equalizer = EqualizerStore(engine: engine)
        let plex = library.map { PlexConnection(library: $0) }
        self.plex = plex
        player = PlayerViewModel(engine: engine, queue: queue, database: library?.database, preferences: preferences,
                                 router: PlaybackRouter(plex: plex, preferences: preferences))
        nowPlaying = NowPlayingService(player: player, library: library)
        mediaKeys = MediaKeyTap(player: player)
        networkSync?.onMerged = { [weak self] in
            await self?.library?.refreshAfterSync()
            await self?.playlists?.reload()
        }
        networkSync?.likedVideos = { [weak self] in self?.videos.syncedLikeKeys ?? [] }
        networkSync?.setLikedVideos = { [weak self] keys in self?.videos.setSyncedLikes(keys) ?? 0 }
        engine.eventHandler = { [weak self] event in
            if case .queueFinished = event { self?.player.queueDidFinish() }
        }
        player.onNewQueue = { [weak self] album in
            guard let self else { return }
            // A whole album started from a grid opens that album's page; anything else returns to the page it was on.
            closeVideo()
            var from = album.map { Location(page: .albums, albums: [$0]) } ?? location
            // On the Artists page, also remember which artist it was (the page itself keeps that separately).
            if from.page == .artists { from.artistKey = UserDefaults.standard.string(forKey: "selectedArtist") }
            playingFrom = from
        }

        #if DEBUG
        // For checking a page by eye during development: `MacBee -debugSmartPlaylist 3` opens Favorites.
        // `MacBee -debugCopyTo 1 -syncDestination <folder> -syncSelection s:3` opens Copy To, scans, and copies.
        if UserDefaults.standard.bool(forKey: "debugCopyTo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                UserDefaults.standard.set("sync", forKey: "tagsSection")
                self?.go(to: .tags)
            }
        }
        let debugSmart = UserDefaults.standard.integer(forKey: "debugSmartPlaylist")
        if let smart = SmartPlaylist(rawValue: debugSmart) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.openPlaylist(smart.playlistId) }
        }
        #endif

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
        if page == .tags && !isInTrackStudio { locationBeforeTrackStudio = location }
        // In Track Studio, library pages open beside it instead of leaving the mode. Music (Home) isn't one of
        // them: it always leaves both studios.
        if isInTrackStudio && Self.browsableBesideTrackStudio.contains(page) {
            trackStudioBrowse = page
            location.albums = []
            return
        }
        if page != .tags { trackStudioBrowse = nil }
        location = Location(page: page)
    }

    static let browsableBesideTrackStudio: Set<SidebarItem> = [.collection, .artists, .albums, .search]

    /// The Track Studio button: enters the mode, or leaves it back to where you were.
    func toggleTrackStudio() {
        if isInTrackStudio {
            trackStudioBrowse = nil
            location = locationBeforeTrackStudio ?? Location(page: .home)
            locationBeforeTrackStudio = nil
        } else {
            go(to: .tags)
        }
    }

    /// Whether this playlist is the one highlighted in the sidebar: a studio's song source, or the open page.
    func isPlaylistHighlighted(_ id: Int64?) -> Bool {
        if isInStudio { return studioSourcePlaylistId == id }
        if isInTrackStudio { return trackStudioSourcePlaylistId == id }
        return selection == .playlists && selectedPlaylistId == id
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
        } else if isInTrackStudio {
            trackStudioSourcePlaylistId = id
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

    /// Opens an album page by its key (from a song's Album column).
    func openAlbum(key: String) async {
        guard let album = try? await library?.database.album(key: key) else { return }
        openAlbum(album)
    }

    /// Shows an artist on the Artists page (from a song's Artist column).
    func openArtist(key: String) {
        UserDefaults.standard.set(key, forKey: "selectedArtist")
        go(to: .artists)
    }

    /// Opens the album of the song that's playing, on the Albums page.
    func showCurrentAlbum() async {
        guard let track = player.currentTrack, let database = library?.database,
              let album = try? await database.album(key: track.albumKey) else { return }
        if isInTrackStudio {
            trackStudioBrowse = .albums
            location.albums = [album]
            return
        }
        location = Location(page: .albums, albums: [album])
    }

    // MARK: - Videos

    /// Plays a video over the window, pausing the music first.
    func playVideo(_ playback: VideoPlayback) {
        if player.isPlaying { player.togglePlayPause() }
        showNowPlaying = false
        videos.markPlayed(playback.likeId)
        videoSession?.stop()
        let session = VideoSession(playback: playback, library: videos)
        videoSession = session
        // A video started while the mini player is open plays there.
        if videoIsMini { videoMiniWindow.show(session, app: self) }
    }

    func closeVideo() {
        guard let session = videoSession else { return }
        videoIsMini = false
        videoMiniWindow.hide()
        session.stop()
        videoSession = nil
    }

    /// Moves the video into its own small window.
    func showVideoMiniPlayer() {
        guard let session = videoSession else { return }
        videoIsMini = true
        videoMiniWindow.show(session, app: self)
    }

    /// Puts the video back over the main window.
    func hideVideoMiniPlayer() {
        guard videoIsMini else { return }
        videoSession?.player.activeHost = "main"
        videoMiniWindow.hide()
        videoIsMini = false
        NSApp.activate()
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(MacBeeApp.mainWindowID) == true }?.makeKeyAndOrderFront(nil)
    }

    func playMovie(_ movie: Movie, resume: Bool) {
        guard let file = movie.file else { return }
        if !resume { videos.savePosition(0, duration: 0, for: file.path) }
        playVideoFile(file, title: movie.title, subtitle: movie.year.map(String.init) ?? "", likeId: movie.id)
    }

    func playVideoFile(_ file: VideoFile, title: String, subtitle: String, likeId: String) {
        playVideo(VideoPlayback(title: title, subtitle: subtitle, file: file, likeId: likeId))
    }

    /// Plays an episode, then carries on through the rest of the show.
    func playEpisode(_ episode: Episode, in show: Show, resume: Bool) {
        if !resume { videos.savePosition(0, duration: 0, for: episode.file.path) }
        let all = show.seasons.flatMap(\.episodes)
        let rest = all.drop { $0.id != episode.id }.dropFirst()
        var playback = VideoPlayback(title: episodeTitle(episode), subtitle: "\(show.title) · \(episode.code)",
                                     file: episode.file, likeId: show.id)
        playback.upNext = rest.map { (episodeTitle($0), "\(show.title) · \($0.code)", $0.file) }
        playVideo(playback)
    }

    // MARK: - Random play (right-click Artists / Albums / Playlists in the sidebar)

    func playRandomArtist() async {
        guard let database = library?.database,
              let artist = try? await database.artists(hidingCompilationOnly: preferences.hideCompilationOnlyArtists)
                .randomElement() else { return }
        player.play(await player.tracks(of: artist).shuffled())
    }

    func playRandomAlbum() async {
        guard let database = library?.database,
              let album = try? await database.albums(sortedBy: .artist).randomElement() else { return }
        await player.playAlbum(album)
    }

    func playRandomPlaylist() async {
        guard let playlists else { return }
        for playlist in playlists.allPlaylists.shuffled() {
            guard let id = playlist.id else { continue }
            let tracks = await playlists.tracks(for: .playlist(id))
            if !tracks.isEmpty { return player.play(tracks) }
        }
    }

    func playMusicVideo(_ video: MusicVideo) {
        playVideoFile(video.file, title: video.title, subtitle: video.folderName, likeId: video.id)
    }

    private func episodeTitle(_ episode: Episode) -> String {
        episode.title ?? "Episode \(episode.number)"
    }

    /// Looks for videos again in the video folders and (for music videos) the music folders.
    func refreshVideos() async {
        await videos.refresh(videoFolders: preferences.activeVideoFolders.map { URL(fileURLWithPath: $0) },
                             musicFolders: library?.folders.filter { $0.isOnline && !$0.folder.isPaused }.map(\.folder.url) ?? [],
                             plex: plex)
    }

    /// Switches a video folder on or off, then looks for videos again.
    func setVideoFolder(_ path: String, paused: Bool) {
        preferences.pausedVideoFolders.removeAll { $0 == path }
        if paused { preferences.pausedVideoFolders.append(path) }
        Task { await refreshVideos() }
    }

    /// Re-scans when the saved list is more than 10 minutes old (opening Videos stays instant).
    func refreshVideosIfStale() async {
        // Wait for the music folders to be known, or music videos would be missed.
        if let library, library.folders.isEmpty, library.stats.tracks > 0 { return }
        if let scanned = videos.catalog.scannedAt, Date().timeIntervalSince(scanned) < 600 { return }
        await refreshVideos()
    }

    /// "Playing From": back to the page the music was started from (or the playing song's album).
    /// In Track Studio it opens beside the studio instead of leaving it (Troy).
    func showPlayingFrom() async {
        if var playingFrom, playingFrom.page != .search || !searchText.isEmpty {
            if let artistKey = playingFrom.artistKey {
                UserDefaults.standard.set(artistKey, forKey: "selectedArtist")
                playingFrom.artistKey = nil // the page's own location doesn't carry it
            }
            if isInTrackStudio {
                if playingFrom.page == .tags { return } // started in Track Studio: already here
                if Self.browsableBesideTrackStudio.contains(playingFrom.page) {
                    trackStudioBrowse = playingFrom.page
                    location.albums = playingFrom.albums
                } else {
                    await showCurrentAlbum()
                }
                return
            }
            location = playingFrom
        } else {
            await showCurrentAlbum()
        }
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
        if preferences.mediaKeysAlwaysMacBee { mediaKeys.start(askForPermission: true) }
        SecondaryClickMonitor.shared.start(fallbackZone: { [weak self] event in
            // The play bar is the bottom strip of the main window; Now Playing covers the whole window.
            guard let self, let window = event.window, window.identifier?.rawValue.hasPrefix(MacBeeApp.mainWindowID) == true
            else { return event.window?.identifier?.rawValue.hasPrefix(MacBeeApp.miniPlayerWindowID) == true }
            return self.showNowPlaying || event.locationInWindow.y <= Metrics.playBarHeight
        }) { [player] in
            if player.currentTrack != nil { player.togglePlayPause() }
        }
        // The permission may be given in System Settings while MacBee is open; try again on coming back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.preferences.mediaKeysAlwaysMacBee else { return }
                self.mediaKeys.start(askForPermission: false)
            }
        }
        library?.periodicCheckInterval = preferences.routineCheck.interval
        await library?.start(checkForChanges: preferences.checkLibraryAtLaunch)
    }
}
