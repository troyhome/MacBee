import Foundation
import MacBeeAudio
import MacBeeLibrary
import Observation

/// What the play bar and library views use to control playback.
/// Connects the engine, the queue and the library database.
@MainActor
@Observable
final class PlayerViewModel {
    let engine: any PlaybackEngine
    let queue: QueueManager
    /// Shown as an alert.
    var errorMessage: String?
    /// Favorites changed in this session, so every list shows the new state without reloading.
    private(set) var favoriteOverrides: [Int64: Bool] = [:]
    /// Bumped after each play is saved, so Home's Recently Played and Play History refresh.
    private(set) var playsRecorded = 0
    /// Bumped after favorites are saved, so the Collection page reloads.
    private(set) var favoritesSaved = 0

    @ObservationIgnored private let database: LibraryDatabase?
    @ObservationIgnored private let preferences: PreferencesStore
    /// Called when a new list of songs starts playing; the album when a whole album was started.
    /// AppModel uses it to remember the page the music was started from ("Playing From" in the sidebar).
    @ObservationIgnored var onNewQueue: ((AlbumSummary?) -> Void)?
    /// Network drive or Plex, per song.
    let router: PlaybackRouter
    @ObservationIgnored private var recorder = PlayRecorder()
    @ObservationIgnored private var playId = 0
    @ObservationIgnored private var recorderTask: Task<Void, Never>?

    init(engine: any PlaybackEngine, queue: QueueManager, database: LibraryDatabase?, preferences: PreferencesStore,
         router: PlaybackRouter) {
        self.engine = engine
        self.queue = queue
        self.database = database
        self.preferences = preferences
        self.router = router
        queue.router = router
        router.database = database
        // A song finished downloading from Plex: line up the next one for gapless playback.
        router.onPrefetched = { [weak engine] in engine?.queueDidChange() }
        recorderTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkPlayThreshold()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    var currentTrack: Track? { queue.current }
    /// The current song is playing from a copy fetched from Plex.
    var isPlayingFromPlex: Bool { router.isFromPlex(engine.currentTrack) }
    var isPlaying: Bool { engine.state == .playing }

    // MARK: - Starting playback

    func play(_ tracks: [Track], startAt index: Int = 0) {
        guard tracks.indices.contains(index) else { return }
        queue.replace(with: tracks, startAt: index)
        if let track = queue.current { start(track) }
        onNewQueue?(nil)
    }

    /// Turns shuffle on and plays the tracks from a random one.
    func playShuffled(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        queue.setShuffled(true)
        play(tracks, startAt: Int.random(in: tracks.indices))
    }

    func playAlbum(_ album: AlbumSummary) async {
        play(await tracks(of: album))
        onNewQueue?(album)
    }

    /// Plays all of an artist's albums, oldest first.
    func playArtist(_ artist: ArtistSummary) async {
        play(await tracks(of: artist))
    }

    /// Plays these tracks after the current one (or now, if nothing is playing).
    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard queue.current != nil else { return play(tracks) }
        queue.insertNext(tracks)
        engine.queueDidChange()
    }

    /// Adds these tracks to the end of the queue (or plays them, if nothing is playing).
    func addToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard queue.current != nil else { return play(tracks) }
        queue.append(tracks)
        engine.queueDidChange()
    }

    func tracks(of album: AlbumSummary) async -> [Track] {
        guard let database else { return [] }
        do {
            return try await database.tracks(inAlbum: album.albumKey)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// All of an artist's tracks, album by album, oldest album first.
    func tracks(of artist: ArtistSummary) async -> [Track] {
        guard let database else { return [] }
        do {
            var tracks: [Track] = []
            for album in try await database.albums(sortedBy: .artist, artistKey: artist.artistKey) {
                tracks += try await database.tracks(inAlbum: album.albumKey)
            }
            return tracks
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        if engine.state == .stopped, let track = queue.current {
            start(track)
        } else {
            engine.togglePlayPause()
        }
    }

    func next() {
        guard let i = queue.currentIndex, let j = queue.index(after: i, userSkipped: true),
              let track = queue.move(to: j) else { return }
        start(track)
    }

    // MARK: - Queue drawer

    /// Plays a song right away and keeps the rest of the queue after it.
    func playNow(_ track: Track) {
        guard queue.current != nil else { return play([track]) }
        queue.insertNext([track])
        next()
    }

    /// Plays an Up Next entry now.
    func playQueueItem(_ id: UUID) {
        guard let track = queue.move(toItem: id) else { return }
        start(track)
    }

    func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpNext(fromOffsets: source, toOffset: destination)
        engine.queueDidChange()
    }

    func removeFromUpNext(_ ids: Set<UUID>) {
        queue.removeFromUpNext(ids: ids)
        engine.queueDidChange()
    }

    func clearUpNext() {
        queue.clearUpNext()
        engine.queueDidChange()
    }

    func toggleShuffle() {
        queue.setShuffled(!queue.isShuffled)
        engine.queueDidChange()
    }

    /// Off → All → One → Off.
    func cycleRepeat() {
        queue.repeatMode = queue.repeatMode.next
        engine.queueDidChange()
    }

    /// Goes back to the start of the track, or to the previous track if near the start.
    func previous() {
        guard let i = queue.currentIndex else { return }
        if engine.progress.elapsed > 3 || i == 0 {
            engine.seek(to: 0)
        } else if let track = queue.move(to: i - 1) {
            start(track)
        }
    }

    func seek(toFraction fraction: Double) {
        guard let duration = engine.progress.duration else { return }
        engine.seek(to: fraction * duration)
    }

    func isFavorite(_ track: Track) -> Bool {
        track.id.flatMap { favoriteOverrides[$0] } ?? track.isFavorite
    }

    /// Favorite or unfavorite the current track.
    func toggleFavorite() {
        guard let track = queue.current else { return }
        setFavorite([track], !isFavorite(track))
    }

    func setFavorite(_ tracks: [Track], _ isFavorite: Bool) {
        guard let database else { return }
        var ids: [Int64] = []
        for var track in tracks {
            guard let id = track.id else { continue }
            favoriteOverrides[id] = isFavorite
            track.isFavorite = isFavorite
            queue.update(track)
            ids.append(id)
        }
        Task {
            do {
                for id in ids { try await database.setFavorite(trackId: id, isFavorite) }
            } catch {
                errorMessage = error.localizedDescription
            }
            favoritesSaved += 1
        }
    }

    // MARK: - Output

    func availableDevices() -> [AudioDevice] {
        engine.availableOutputDevices()
    }

    /// `nil` follows the macOS default output.
    func selectDevice(uid: String?) {
        var settings = engine.settings
        settings.deviceUID = uid
        apply(settings)
    }

    /// Changes output settings from Preferences > Audio and saves them.
    func updateOutputSettings(_ change: (inout OutputSettings) -> Void) {
        var settings = engine.settings
        change(&settings)
        apply(settings)
    }

    func toggleExclusiveMode() {
        var settings = engine.settings
        settings.exclusiveMode.toggle()
        apply(settings)
    }

    func setVolume(_ volume: Float) {
        engine.setVolume(volume)
        if engine.settings.volumeMode == .software { OutputSettingsStore.save(engine.settings) }
    }

    private func apply(_ settings: OutputSettings) {
        engine.apply(settings)
        OutputSettingsStore.save(settings)
    }

    // MARK: - Helpers

    private func start(_ track: Track) {
        playId += 1
        Task {
            do {
                let url = try await router.playableURL(for: track)
                // Skip if another song was started while this one was downloading.
                guard queue.current?.path == track.path else { return }
                try await engine.play(url)
            } catch {
                errorMessage = "Couldn't play “\(track.displayTitle)”. \(error.localizedDescription)"
            }
        }
    }

    /// Records a play in the library once enough of the track has been heard.
    private func checkPlayThreshold() {
        guard engine.state == .playing, let track = queue.current, let id = track.id,
              router.matches(track, engine.currentTrack), let database else { return }
        let duration = engine.progress.duration ?? track.duration
        guard recorder.shouldRecord(url: track.url, playId: playId, advance: queue.advanceCount,
                                    elapsed: engine.progress.elapsed,
                                    threshold: preferences.playCountRule.threshold(forDuration: duration)) else { return }
        Task {
            do {
                try await database.recordPlay(trackId: id)
                playsRecorded += 1
            } catch {
                // Not worth interrupting playback for; the next play will try again.
            }
        }
    }
}
