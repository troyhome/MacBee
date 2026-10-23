# MacBee — project brief for Claude Code

**Always read `MACBEE_PLAN.md` before starting any phase.** It has the full plan, decisions and design system.

MacBee is a native macOS music player (Swift / SwiftUI) that combines MusicBee-style bit-perfect
playback with a dark, TIDAL-inspired interface. It is being built in phases.

## About the user
- New to programming and Terminal. Explain briefly, in plain language, no jargon.
- Prefers short answers and no emojis.
- Give exact steps when something must be done by hand; otherwise just do it.

## Decisions already made
- Audio engine: SFBAudioEngine (~> 0.14.0), wrapped by our own `PlaybackEngine` protocol.
- Formats: FLAC, ALAC, WAV, AIFF, MP3, AAC, DSD (.dsf). DSD plays as DoP (bit-perfect, DAC must support it) or DSD64→PCM (default).
- Minimum macOS 14 Sonoma. Everyday build = direct download, no sandbox. A separate sandboxed "AppStore" build
  configuration exists for the Mac App Store (Troy chose two builds, 2026-10-23); see "App Store build" in Status.
- Exclusive (hog) mode: off by default, one-click toggle in settings and the play bar.
- Volume: hardware (DAC) volume by default; optional software volume, flagged "not bit-perfect" below 100%.
- Music lives on a network drive mounted at `/Volumes/2 Set Music` (~9,500 tracks, growing). More folders can be added later.
- Network playback: each track and the next one are loaded fully into memory before playing (fixed real dropouts).
- The Mac currently has no external DAC; the "BoomAudio" output (Boom 3D app) adds effects, so tests target "MacBook Air Speakers".
- Code signing (2026-10-18): automatic signing with Troy's Apple team DA9YJ36D24 ("Apple Development"), plus
  `MacBee.entitlements` (Keychain Sharing, group `$(AppIdentifierPrefix)com.troyhomenchuk.MacBee`). Needed so the
  Plex token lives in the data protection keychain (`MacBee/Plex/KeychainStore.swift`) with no "wants to access key"
  prompts; the old self-signed "MacBee Local Signing" cert got error -34018 there. `Tools/macbee.sh` passes
  `-allowProvisioningUpdates` so Xcode renews the signing profile on each build. Each Mac must be signed in to
  Xcode > Settings > Accounts with Troy's Apple ID. Troy's paid Apple Developer Program membership was approved 2026-10-19 (same team ID); signing profiles now
  last a year. If a build ever gets a 7-day profile again, delete ~/Library/Developer/Xcode/UserData/Provisioning
  Profiles/* and rebuild.
  Don't go back to ad-hoc ("-") or self-signed signing.
- Virtual output devices (BoomAudio, Loopback, BlackHole; transport type virtual or unknown) are never switched
  in sample rate or bit depth: doing so made Boom 3D produce loud noise. They show as "not bit-perfect".
- Architecture: MVVM, small files, no giant single-file dumps. Placeholder protocols for a future tag editor and Plex.

## Where the project lives and how to build
- The project is at `~/Projects/MacBee` on each Mac (not in iCloud) and is backed up and shared through a private
  GitHub repository. Troy works on two MacBook Airs, never on both at once.
- Routine: at the start of a session `git pull`; after finishing a piece of work, commit and `git push`, so the
  other Mac can pick it up. Troy is new to Git, so do this for him and say it plainly ("saved and sent to GitHub").
  Chats don't sync between Macs; this file and MACBEE_PLAN.md carry the context, so keep them current.
- Build files must never go inside the project folder (they're large and change constantly). Always use `Tools/macbee.sh`:
  `Tools/macbee.sh build` (app), `Tools/macbee.sh test` (package tests), `Tools/macbee.sh run` (open the app),
  `Tools/macbee.sh install` (optimized build copied to /Applications/MacBee.app, the copy Troy uses day to day;
  re-run it after changes he should get). `Tools/macbee.sh update` = `git pull` + install, skipped when the
  installed copy already matches (commit stored in `~/Library/Developer/MacBee/installed-commit`).
  An "Update MacBee" app in /Applications (AppleScript, made by `Tools/macbee.sh updater`) runs `update`
  and shows the result; log in `~/Library/Logs/MacBee-update.log`. Its GitHub sign-in is the GitHub CLI at
  `~/.local/bin/gh` (git uses it for credentials).
  It puts everything in `~/Library/Developer/MacBee`. For `swift run`/`swift test` by hand, add
  `--scratch-path ~/Library/Developer/MacBee/<PackageName>`.
- Per Mac (not synced): the music database and play history (`~/Library/Application Support/MacBee/`), and the
  "MacBee Local Signing" certificate (each Mac needs its own, made in Keychain Access).

## Status
- Phase 1 DONE and tested by ear: `Packages/MacBeeAudio` (engine, device control, gapless, rate switching, `macbee-play` test tool).
- Phase 2 DONE and verified: `Packages/MacBeeLibrary` (GRDB/SQLite library, scanner, cover-art cache,
  folder monitoring, `macbee-library` test tool). Full scan of the drive: 9,444 tracks, 862 albums, 224 artists
  (3 Curve FLACs unreadable).
- Phase 3 DONE: `MacBee.xcodeproj` + sources in `MacBee/` (App, Theme, Shell, Search, Playback, PlayBar, Library,
  Menus, Home, Common, Services). Sidebar with search (⌘F), two-column Artists, Albums grid, album pages,
  play bar (shuffle/repeat, quality badge, Bit-Perfect badge, device picker with rates, exclusive mode, volume),
  gapless queue with Play Next / Add to Queue, right-click menus, favorites, play counting, keeps playing when
  the window closes, Dock menu, media keys + Control Center. App icon drawn by `Tools/make-icon.swift`.
  The project uses a synchronized folder, so new files in `MacBee/` are picked up automatically.
- Phase 4 DONE (checked by Troy): Home screen in `MacBee/Home/` (stats, Recently Played, Suggested Mixes,
  Recently Added, Forgotten Gems, Play History by day, Library scan panel, welcome screen when no folders).
  Queries in `MacBeeLibrary/Database/LibraryDatabase+Home.swift` with tests in `HomeQueriesTests`.
- Phase 5 DONE (checked by Troy): Now Playing view (`MacBee/NowPlaying/`, opens from the play-bar cover, Esc closes,
  full-screen button), queue drawer (`MacBee/Queue/`, reorder/remove/clear Up Next, session history), mini player
  window (`MacBee/MiniPlayer/`, stay-on-top pin, closing it brings the main window back). Media keys, Control
  Center and the Dock menu were done earlier.
- Phase 6 DONE (checked by Troy): Preferences window (⌘,) in `MacBee/Preferences/` with General, Appearance,
  Library, Audio, Plex (placeholder) and Tag Editor (choose app) tabs. App settings live in `PreferencesStore`;
  audio in `OutputSettingsStore` (now with loadIntoMemory); theme/accent (incl. custom color) in `ThemeStore`.
- The "Collection" page is called "Collections" in the UI (Troy, 2026-10-17); code names stay `collection`.
- Phase 7 DONE (checked by Troy): playlists + nested folders (DB migration v2; `LibraryDatabase+Playlists.swift`,
  `M3UPlaylist`, tests in `PlaylistTests`), app code in `MacBee/Playlists/` (PlaylistStore, sidebar tree, pages,
  drag payloads as "macbee:..." strings), Add to Playlist menus in `MacBee/Menus/`, Playlist Studio in
  `MacBee/Studio/` with a reserved TagEditorSlot. Smart playlists (optional) not done.
  Studio mode (Troy's design): clicking Playlist Studio enters it, clicking it again returns to where you were;
  Music/Artists/Albums/Search leave it. In studio mode a sidebar playlist click (or dropping a playlist on the
  middle pane) shows that playlist's songs there ("Back to Library" returns); dropping a playlist on the right pane
  adds all its songs. Search-in checkboxes (Artist, Album, Song title; none = everything). Panes tinted with the accent.
- Phase 8 DONE (checked by Troy 2026-10-17, both Macs):
  - Tag editor = TagBee (`/Applications/TagBee.app`, default when nothing valid is chosen). `ExternalTagEditor`
    (MacBee/Services) opens songs there and watches the files for ~1 hour, re-reading them via
    `MusicLibrary.refreshFiles` when saved. "Edit Tags in TagBee…" in song/album menus and Playlist Studio.
  - Plex = an automatic away-from-home route to the SAME library (Troy's Plex serves the 2 Set Music files), not a
    second library. `MacBee/Plex/` (PlexAPI, PlexConnection: PIN sign-in via browser, token in Keychain, servers,
    connection order home > internet > relay), `PlexMatcher` + `plexLink` table (DB v4) pair Plex files with library
    songs by path below the music folder. `PlaybackRouter` (MacBee/Playback) picks drive vs Plex per song
    (Preferences > Plex: Automatic / Always drive / Always Plex), downloads originals to
    ~/Library/Caches/MacBee/Plex (3 GB limit) so playback stays bit-perfect. Play bar shows "PLEX".
- Phase 8 testing (started 2026-10-17): Troy has a 10-step checklist (Edit Tags in TagBee from song/album menus and
  Playlist Studio; Plex sign-in in Preferences > Plex; server + library pick and match count; "Always Plex" playback
  with the PLEX badge; replay from cache; back to Automatic; optional: eject the drive and play via Plex).
  Results so far (record each result and fix here as it comes in):
  - 2026-10-17, second Mac: "Edit Tags in TagBee" was greyed out. Cause: TagBee was installed ~2 min after MacBee
    started, and MacBee only looked for TagBee at launch. Fixed: it also looks whenever MacBee comes to the front
    (`PreferencesStore.useDefaultTagEditorIfNeeded`). Confirmed working.
- Phase 9 DONE (checked by Troy 2026-10-17): MacBee 1.0. About window with credits
  (`MacBee/App/AboutCommand.swift`), `Tools/macbee.sh dmg` (makes ~/Desktop/MacBee-<version>.dmg with an
  Applications shortcut). Decided 2026-10-17: MacBee is just for Troy, so no Apple Developer Program for now (he may
  join later to share it; signed+notarized copies keep working after membership ends). Version set to 1.0.
  Performance pass (2026-10-17, from reading the code): cover cache now limited to 150 MB instead of 800 covers
  (could reach 500+ MB); album tiles only draw a shadow while hovered. Troy's timings (launch, Albums
  scroll, page switches, memory in Activity Monitor) -> Troy: "all good".
- All original phases (1-9) are done.

## Post-1.0 roadmap (docs/ROADMAP.md)
Troy's new 5-phase roadmap (received 2026-10-17). Rule: one phase at a time; never start the next phase until
Troy confirms the current one passes its gate (zero compiler errors, all tests pass, his smoke tests succeed).
- Roadmap Phase 1 PASSED (confirmed by Troy 2026-10-18, after the fixes and the Videos section below).
  (Built 2026-10-17: app builds with no errors or warnings; package tests pass.) What was done:
  - Search: top margin on the results list (`.contentMargins`) so the first artist row clears the toolbar.
  - Play bar: format badge removed from the left track info (`TrackInfoText`); format shows only on the right
    (`SignalPathBadge`, now with kbps for MP3/AAC).
  - Album page header: round Play Next, Play Later, Add to Playlist…, Favorite (hearts every song; the album
    counts as a favorite when all its songs are) buttons next to Shuffle/Play (`AlbumDetailView`).
  - Collection page (`MacBee/Collection/`, sidebar item under Music): segmented Playlists / Albums (favorite
    albums) / Tracks (favorite songs) / Videos (placeholder) / Saved Mixes (placeholder until roadmap Phase 3).
    Queries in `LibraryDatabase+Collection.swift`, tests in `CollectionQueriesTests`. Reloads when
    `PlayerViewModel.favoritesSaved` changes.
  - Sidebar under Playlist Studio: `LibrarySourceStatus` (Local library / Plex / Library offline, same rules as
    PlaybackRouter) and a Force Rescan button (`MusicLibrary.forceRescanAll`, re-reads every file;
    `ScanPlanner.plan(rereadAll:)`), with a confirmation.
  - Preferences: Plex tab removed; its sections (`PlexPreferenceSections`) are at the bottom of the Library tab.
  - `HorizontalCarousel` (Common/): hover arrows on every horizontal row (Home album rows, mixes, search
    artists/albums). Pages the underlying NSScrollView by 80% of its width.
  - Media keys: `NowPlayingService` reports "playing" the instant playback starts/resumes/changes song (was up to
    1 s later) and enables only the commands MacBee handles. macOS gives media keys to the app that most recently
    reported playing; an app can't fully block others that start playing afterwards.
  - Two-finger click (secondary click) skips to the next song on the play bar, Now Playing and the mini player
    (now `secondaryClickPlaysPauses()`). Deliberately NOT window-wide: that would break every right-click menu
    (Edit Tags, Add to Playlist…). Revisit if Troy wants it elsewhere.
  - Fixes after Troy's first test (2026-10-17):
    - Album actions are now labeled pills on a row under Play: Play Next, Add to Queue (Troy found "Play Later"
      unclear), Add to Playlist, Favorite/Favorited. The old round + menu rendered badly.
    - Collection and Videos pages have a back arrow (`app.canGoBack`).
    - "Playing From" sidebar row (shown while something is loaded): returns to the page the music was started
      from (`AppModel.playingFrom`, set via `PlayerViewModel.onNewQueue`; a whole album opens its album page).
    - Videos sidebar page + Collection Videos tab (`MacBee/Videos/`): finds MP4/M4V/MOV in the music folders
      (not in the database; re-searched when the page opens), thumbnails via AVAssetImageGenerator, plays in an
      AVKit overlay over the window (Esc closes; music pauses; starting music closes the video).
    - Media keys: an event tap (`MediaKeyTap`, needed Accessibility) was added here and REMOVED 2026-10-22 for the
      App Store. See "Media keys rule" below.
    - Two-finger click now pauses/resumes instead of skipping (`secondaryClickPlaysPauses()`).
  - Fixes after Troy's second test (2026-10-17):
    - Playing a video crashed MacBee (SwiftUI `VideoPlayer` from _AVKit_SwiftUI aborts in metadata init on
      macOS 26). Now uses AppKit `AVPlayerView` via NSViewRepresentable. Don't go back to SwiftUI VideoPlayer.
    - Two-finger click did nothing (the hitTest overlay trick doesn't get right clicks in SwiftUI). Now an app-wide
      local NSEvent monitor (`SecondaryClickMonitor`, started in AppModel.start) checks right clicks against
      registered zones (`secondaryClickPlaysPauses()` = background zone view) and toggles play/pause.
    - Videos page has a search box; videos can be liked (heart on hover / in the player). Likes are paths in
      UserDefaults "likedVideos" (per Mac, not in the DB). Collection > Videos shows liked videos only.
  - Fixes after Troy's third test (2026-10-17):
    - Two-finger pause confirmed working by Troy (the zone monitor was fine; earlier "nothing" was likely
      two clicks pausing and resuming).
    - Search box above the Artists list (`FilterField`, Common/, also used by Videos).
    - A–Z strip (`AlphabetIndex`, Common/) beside the Artists list and the Albums grid/list (Albums: only when
      sorted by Artist or Title). Placed in an HStack next to the ScrollView, not as an overlay, so the scroll
      bar doesn't cover it.
    - Albums toolbar Grid / List switch (`AlbumLayout`, @AppStorage "albumLayout"); list rows have round covers.
    - `ColumnResizer`: 12-pt grab area above both neighbouring columns (zIndex), accent line while hovered or
      dragged, double-click restores `defaultWidth`. Troy found the old 7-pt one hard to grab.
  - Videos section rebuilt (2026-10-17, Troy's request, outside the roadmap): Apple TV style.
    - New local package `Packages/MacBeeVideo` (in the Xcode project as a third local package; `macbee.sh test`
      runs its tests): `VideoNameParser` (titles/years/SxxEyy/4K/HDR from messy names), `VideoScanner` (movies,
      shows grouped by top folder + season, posters next to files, .nfo genres; skips samples, extras and files
      < 20 MB), `VideoCatalogStore` (cache in ~/Library/Application Support/MacBee/videos.json), `MPVPlayer` +
      `MPVVideoView` (libmpv via MPVKit, LGPL product "MPVKit", pinned exact 1.1.0-n9.0.2; vo=gpu-next, MoltenVK,
      videotoolbox). Troy OK'd downloading MPVKit. Checked: MKV and a 4K HDR HEVC MKV play.
    - App side `MacBee/Videos/`: VideosView (sidebar Recently Played / Movies / TV Shows / Music Videos / Genres, per Troy;
      Recently Played uses UserDefaults "videoLastPlayed" [title id: date], set in AppModel.playVideo;
      Continue Watching row on Movies and TV Shows; search), Movie/Show detail pages, VideoPlayerOverlay + VideoControls (auto-hide,
      Space/←/→/Esc, audio + subtitle menus, volume, resume positions, next episode autoplay). Likes, positions and
      watched are per Mac in UserDefaults ("likedVideos", "videoPositions", "watchedVideos").
    - Preferences > Library > Video folders (`PreferencesStore.videoFolders`). Troy's: "/Volumes/2 Set 6TB/MOVIES SHOWS"
      (set on the second MacBook Air; the first Mac needs it added in Preferences). Music folders are scanned for
      music videos only.
    - Plex enrichment (`Plex/PlexVideoIndex.swift`, `PlexAPI+Video.swift`): matches by file name against Plex movie
      and TV libraries for titles, years, genres, summaries and posters (cached in ~/Library/Caches/MacBee/Posters).
    - The old AVKit/AVPlayerView video player is gone; everything plays through mpv now.
    - Stills for videos without posters (music videos, and movies/shows Plex doesn't know): `VideoThumbnailer`
      (MacBeeVideo) grabs a frame 10% in with mpv `screenshot-raw` (the LGPL build has no image encoders, so
      vo=image fails) and saves a JPEG via ImageIO in ~/Library/Caches/MacBee/VideoFrames. Shown in the same 2:3
      card as posters (blurred fill + whole frame); the card is a fixed 2:3 `Color.clear` with the image as overlay
      so wide stills can't stretch the grid. `VideoFrames` actor limits it to 2 at a time.
    - Mini player = its own floating NSPanel (`VideoMiniWindow`), resizable at 16:9, stays above other windows;
      "Back to MacBee" (or double-click) returns the video to the main window; its close button stops the video.
      Playback state lives in `VideoSession` (AppModel.videoSession: MPVPlayer, current item, next episodes,
      position saving) so it survives the move. `MPVPlayer.surface` is the one NSView mpv draws into; each
      `MPVVideoView` adopts it (reparenting), because mpv's `wid` layer can't change after start. It adopts only in
      makeNSView or when the surface is orphaned: adopting on every update pulled the picture back out of the mini
      window (Troy saw black with sound). Checked: playback
      continues and the drawable resizes when the surface moves windows. (The first in-window version cropped the
      picture; Troy asked for a separate window.)
    - Show pages list seasons as tabs (was a pull-down menu), per Troy.
- Roadmap Phase 2 BUILT 2026-10-18, waiting for Troy's smoke tests:
  - DB migration v5: folder.priority + folder.isPaused; track.isPaused + track.duplicateOf. Library queries use
    `LibraryDatabase.visible()` (not missing, not paused, not a duplicate copy); playlists use `playable()` (a
    duplicate someone put in a playlist stays). `refreshVisibility()` re-flags paused songs and re-runs
    `DuplicateFinder` (artist + title + album normalized, lengths within 2 s; best = highest-priority folder,
    then quality, then lowest id). Runs at launch, after scans that changed anything, and on folder order/pause
    changes. On Troy's library: 98 duplicates (e.g. Art School Girlfriend album twice, Appetite twice) of 9,449.
    Backup of the DB before this migration: ~/Library/Application Support/MacBee/Library-before-phase2.sqlite.
  - Preferences > Library > Music folders: drag rows to set priority (draggable/dropDestination, not onMove),
    switch per folder to pause (paused folders aren't scanned or shown). "Artists" section: Hide
    compilation-only artists (`PreferencesStore.hideCompilationOnlyArtists`; `artists(hidingCompilationOnly:)`
    = HAVING MIN(isCompilation) = 0).
  - Failover: `PlaybackRouter` plays another folder's copy (`alternativeFiles(forTrackId:)`, best priority first,
    paused folders skipped) when the song's file can't be reached, before falling back to Plex.
  - Home: `SourceBadge` (Local Library / Plex Server / Library offline) with a switch: on = playbackSource .plex,
    off = .automatic. It switches where songs play from; the library list itself stays the same songs.
  - Fixes after Troy's first Phase 2 test (2026-10-18):
    - Duplicates matched by `DuplicateFinder.fingerprint` (letters/digits only), so ’ vs ' and punctuation
      don't matter (Guns N' Roses showed twice).
    - Compilation detection: DB v6 `track.onCompilation`, set in `refreshVisibility` when tagged as compilation,
      filed under Various Artists, or the song's folder holds 3+ different artists (many compilations aren't
      tagged; e.g. 4 Non Blondes on "If I Were A Carpenter"). Hidden artists on Troy's library: 19 of 226.
    - Tags page (`MacBee/Tags/`): Duplicates (every song with several copies; per copy: Remove from Library,
      Keep Only This Copy, Show in Finder, Move File to Trash; Remove All Extra Copies; Restore Removed Copies)
      and a TagBee tab (opens TagBee; full integration is Phase 5). "Remove from Library" sets DB v6
      `track.isExcluded` (kept across scans, hidden everywhere, playlists too). Trash uses
      FileManager.trashItem only, never a permanent delete; drives without a Trash leave the file alone.
    - Duplicates page round 2 (Troy): folder menu ("All folders" / "Only <folder>": duplicates inside one
      folder), tick boxes + Select All/Deselect All (ticks extra copies only) with Remove from Library and
      Delete from Disk… at the top, Show in Finder button per copy, full path shown while hovering a row.
      Delete = Trash first; on drives without a Trash (Troy's "music" SMB share has none, "2 Set Music" has
      one) a second confirmation, then a permanent delete. Troy asked for deleting from disk.
    - Collections (2026-10-18, Troy): tabs Playlists / Various Artists / Saved Mixes, then a heart group with the
      liked Albums / Tracks / Videos (`CollectionTabs`). Various Artists = `compilationAlbums()`: visible songs with
      onCompilation, grouped by album title, albumKey "compilation:<lowercased title>" (handled by
      `tracks(inAlbum:)`). Compilation folder rule tightened: only songs with no Album Artist tag, 3+ different
      main artists ("feat." stripped) and no artist with half the folder's songs (Slayyyter etc. were wrongly
      caught). Troy retagged "If I Were A Carpenter" in TagBee (Album Artist = Various Artists).
    - Now Playing view has a queue button (top right) that opens the same QueueDrawer beside it (Troy).
    - MP3 compilation bug: SFBAudioEngine treats any ID3 TCMP frame as "compilation", even "0". `ID3Compilation`
      (Scanning/) reads the frame's value for MP3s. One-time re-read of MP3s marked compilation at launch
      (UserDefaults "MacBee.rereadMP3Compilations.v1"). Mintzkov's albums were under Various Artists because of it.
      `refreshFiles` (tag editor saves) now re-runs `applyVisibility` (duplicates/compilations).
    - Artist page layout switch (header, next to Play; @AppStorage "artistLayout"): "Albums and songs" (original)
      or "Overview (TIDAL style)" = `ArtistOverviewView`: Albums (covers), EPs & Singles (<= 6 songs and < 30 min;
      <= 3 = Single), Mixes (`artistMixes(for:)`: <Artist> Radio with similar artists, Top Tracks, Deep Cuts,
      Favorites), Videos (music videos whose title/folder has the artist's name), Similar Artists
      (`similarArtists(to:)`: genre overlap, compilations left out).
    - Artist header (name, layout switch, Play/Shuffle) stays fixed above the scrolling list in both layouts.
    - Music videos found in more than one music folder show once (same file name; first folder in priority order
      wins). Paused music folders aren't searched for music videos.
    - Playing From remembers the artist when music starts on the Artists page (`Location.artistKey`, restored into
      @AppStorage "selectedArtist").
    - "Tags" sidebar item renamed "Track Studio" (code still `.tags` / `MacBee/Tags/`); Playlist Studio row moved
      right under it. Duplicates tab has a Songs / Videos switch: `VideoDuplicatesView` lists movies with several
      files and music videos with `otherFiles` (same name in another folder/drive/format), with Show in Finder and
      Delete from Disk (Trash, else confirm permanent). Video cards' right-click menu has Show in Finder.
    - Track Studio header: Duplicates / TagBee tabs beside the title (`PillTabs`, Common/, tabs with icons; also
      Songs/Videos and Collections tabs). Duplicates: "Remove All Extra Copies" replaced by **Auto Select** (ticks
      each song's smallest file; equal sizes -> a copy that isn't the shown one), placed before Remove from Library
      / Delete from Disk. **Accept** / Show accepted / Un-accept: DB v7 `track.duplicateAccepted` (all copies of a
      song marked; `duplicateGroups(accepted:)`); videos keep accepted ids in UserDefaults "acceptedVideoDuplicates".
      The video duplicates list has the same tick boxes, Select All, Auto Select, Delete and Accept.
    - Plex video details are saved in ~/Library/Application Support/MacBee/plex-videos.json (`PlexVideoIndex`,
      with local poster paths) and re-applied after every video scan, so posters/titles survive a scan while Plex
      is unreachable or signed out (that's how they disappeared once, right after the keychain change).
    - Video duplicates have the same tools as songs: Duplicates in (video + music folders), Remove from Library
      (UserDefaults "excludedVideos"; the next copy shows instead), Restore Removed Copies, Accept, Auto Select.
    - Troy added a second music folder (/Volumes/music, mostly the same songs): ~9,000 duplicate groups; the
      library shows each once.
- Roadmap Phase 2 PASSED (Troy, 2026-10-18: "Let's move on").
- Roadmap Phase 3 BUILT 2026-10-18, waiting for Troy's smoke tests:
  - DB v8: playlist.capacitySeconds; savedMix + savedMixItem tables. Backup before:
    ~/Library/Application Support/MacBee/Library-before-phase3.sqlite.
  - M3U: export asks for Relative paths (with "../" from where it's saved; full path when on another drive) or
    Full paths (`M3UPlaylist.PathStyle`); .m3u or .m3u8. Import matches paths from other computers by their last
    1–3 path parts when the exact path isn't in the library (`tracks(atPaths:)`).
  - Music page: "Refresh Suggestions" on Suggested Mixes (new seed, `HomeViewModel.refreshMixes`); bookmark on a
    mix card / right-click "Save to Saved Mixes" (`saveMix`); Collections > Saved Mixes lists them (remove via
    right-click).
  - Smart playlists (`SmartPlaylist`, negative playlist ids -1/-2/-3): Recently Added (50), Most Played (100,
    played at least once), Top Rated (150 favorites, by rating then plays; 2026-10-18 Troy: renamed "Favorites", heart icon,
  all favorites, listed first; code name still `.topRated`). Top of the sidebar's playlists;
    `SmartPlaylistView` (Play, Shuffle, Save as Playlist); usable as a Playlist Studio source
    (`tracks(matching:)` handles negative ids) and draggable.
  - MiniDisc: Playlist Studio "New" menu > New 74min / 80min MD Mix (playlist named "<template> <date>" with
    capacitySeconds); studio header has a Disc limit picker, `CapacityBar` (time used of 74:00/80:00, Overtime red,
    Underfill orange when > 7 min free) and Auto-fill (`CapacityFiller.fill`, from the studio's filtered songs,
    shuffled, never over the limit). Playlist pages show the bar too.
  - Fixes after Troy's Phase 3 test: music videos vanished (a video scan ran before the music folders were
    loaded, so it found none and replaced the list). Now the stale-refresh waits for the folders, and a scan that
    couldn't reach any music folder keeps the previous music videos. Playlist Studio: double-click / Return plays
    or pauses a song (`PlayerViewModel.playOrToggle`) in both lists (adding is drag, Add Selected, ⌘Return); the
    studio playlist's Play button is a small play/pause icon.
- Roadmap Phase 3 PASSED (Troy, 2026-10-18: "next").
- Roadmap Phase 4 BUILT 2026-10-18, waiting for Troy's smoke tests:
  - Device Sync = Track Studio tab (`Tags/DeviceSyncView.swift`; logic in MacBeeLibrary `Sync/DeviceSync.swift`,
    tested): choose a device/folder (UserDefaults "syncDestination"), tick smart playlists / playlists / saved mixes
    ("syncSelection"), Check What Changes, Sync Now (progress, Stop). Songs -> Artist/Album/## - Title.ext
    (disc prefix "2-03" on multi-disc; FAT-unsafe characters -> "_"), Playlists/<name>.m3u8 with "../" paths,
    copies only when missing or a different size, removes only files listed in the device's .macbee-sync.json
    (what MacBee put there before) and cleans empty folders.
  - Lyrics (`Lyrics/Lyrics.swift`): `LyricsReader` = embedded tag lyrics first (SFB metadata.lyrics; LRC-formatted
    text shows timed), then <same name>.lrc next to the file (`LRCParser`: multiple stamps per line, [offset:]).
    Now Playing `LyricsPanel`: timed lines highlight and scroll with playback; click a line to jump there.
    Troy's 2 Set Music has ~878 .lrc files.
  - Plex videos debug: Keychain reads log their OSStatus (category "Keychain"); PlexVideos log said "not signed in"
    on 2026-10-18 02:14 right after a reinstall, i.e. the token wasn't readable at that launch.
  - Fixes after Troy's Phase 4 test: lyrics button (quote bubble) next to the queue button opens `LyricsDrawer`
    (shares the right-hand spot with the queue). Timed lyrics win over embedded plain text (Troy wants them in
    time): embedded timed -> .lrc -> embedded plain; plain lyrics are spread over the song
    (`LyricsReader.estimatedTiming`) so they scroll along too. Device Sync has "Entire library" (copies every
    song, no playlist file). Two-finger tap stopped working: diagnostic log added (category "SecondaryClick").
- Roadmap Phase 4 PASSED (Troy, 2026-10-18: "Next"). Plex posters came back after Troy signed in to Plex again
  (the keychain change on the other Mac had lost the token on this Mac: both keychains returned -25300).
- Smart playlist pages (Favorites, Recently Added, Most Played) are TIDAL-style (`SmartPlaylistView` +
  `MacBee/Library/TrackTable.swift`): Play/Shuffle pills, Filter tracks, sortable #/Title+cover/Artist/Album/
  Date Added/Time columns (sticky header; click = sort, again = reverse, third = page order), + and heart per
  row, artist/album names open their pages. DB v9: `track.favoritedAt`, kept by trigger `trackFavoritedAt`
  (any isFavorite change); Favorites ordered newest-hearted first, Date Added = hearted date (older favorites
  fall back to dateAdded). Debug-only launch arg `-debugSmartPlaylist 3` opens Favorites for checking by eye.
- Lyrics found online (`MacBee/NowPlaying/LyricsService.swift`, `MacBeeLibrary/Lyrics/LyricsFinder.swift`):
  Settings > General > Lyrics "Find missing lyrics online" (default on). When a song starts (RootView task on
  currentTrack) and it has no lyrics, LRCLIB (lrclib.net, no key; /api/get then /api/search within 3 s of the
  length; timed lyrics preferred) is asked, and the result is saved as <song>.lrc next to the file (falls back
  to App Support/MacBee/Lyrics/<name>-<hash>.lrc if read-only; `LyricsReader.savedCopiesFolder`). Misses are
  remembered 14 days (UserDefaults "lyricsNotFound"). Live test runs with MACBEE_ONLINE_TESTS=1.
- Video folders can be paused like music folders: `PreferencesStore.pausedVideoFolders` / `activeVideoFolders`,
  `AppModel.setVideoFolder(_:paused:)` (rescans videos). Switches in Settings > Library > Video folders and on
  the Music page's library panel (`VideoFolderStatusRow`).
- Copy To rebuilt (Troy): Scan Device -> report (new / changed: newer mtime or other size / moved: MacBee's
  own copy under an outdated name / found elsewhere: same song by tags (artist|title|album + length within 2 s)
  under another name, not MacBee's / unchanged / unneeded / other files) with choices (`DeviceSync.Choices`:
  copy new, replace changed+moved, elsewhere = leave theirs (playlists point at them) / replace / keep both,
  remove unneeded) -> Start Copy -> `DeviceSync.Job` of operations run by `CopyToRunner` (AppModel.copyTo) on
  a background task: Pause / Resume / Stop, copies via a .macbee-part temp file, auto-pause when the device
  disappears or is full, job saved to App Support/MacBee/copy-to-job.json (survives unplug and quit), manifest
  saved every 5 s; finished report (copied, replaced, renamed, removed, failures, size, time). The old freeze was
  the view re-statting every file's size on each progress update. Debug-only `-debugCopyTo 1` auto-scans+copies.
- Two-finger pause REMOVED (Troy, 2026-10-19): SecondaryClickPlayPause.swift deleted; right-click is for menus now.
  Play-bar cover right-click = `PlayingSongMenu` (Add to Playlist, Go to Album, Go to Artist, Send to TagBee, Show
  in Finder). Album page: Shuffle, Play, heart, and `AlbumMoreMenu` "…" (same menu as artist-page album cards:
  Play Next, Add to Queue, Add to Playlist, Send to TagBee, Show in Finder); the labeled pills are gone.
  `EditTagsButton` now reads "Send to TagBee".
- Video folders have priority like music folders (list order): VideoScanner ranks files by folder; a movie's
  shown copy and each episode's copy come from the first folder that has it (then 4K, then size). Episodes are
  one entry per season+number (`Episode.otherFiles` holds the other copies; shown in Track Studio > Duplicates >
  Videos; excluded copies promote the next). Movies without a year merge into the one dated film of that title.
  `AppModel.videoCatalogVersion` (2) forces one rescan when the scanner changes.
- Edits in TagBee show up automatically even when TagBee renames files as it saves: ExternalTagEditor sees a
  watched file vanish and calls `MusicLibrary.refreshDirectory` (marks gone files missing, re-reads the folder,
  watches the new names). Moved-file matching also accepts same folder + same title + length (size may differ),
  full scans flag missing files BEFORE saving new ones (undone if cancelled/offline), and `Track.apply` clears
  isMissing. Embedded pictures with no data are skipped (some MP3s carry an empty one before the real cover);
  one-time re-read of songs without artwork ("MacBee.rereadSongsWithoutArtwork.v1").
- Track Studio song covers have a preview button (`PreviewArtwork` in TrackRow.swift, shown on hover or for the
  playing song): plays the song now with `player.playNow` (queue kept after it); on the playing song it pauses/resumes.
- Releases: `Tools/macbee.sh release [version]` bumps MARKETING_VERSION (1.0 -> 1.1 by default) and the build number,
  builds the .dmg, commits "MacBee X", tags vX, pushes, and runs `gh release create` with the .dmg. Needs Troy to
  install gh (GitHub pkg installer, no Homebrew on CMBA) and `gh auth login` once per Mac. Releases are downloadable by
  anyone (repo made PUBLIC 2026-10-19 at Troy's request; history scanned for secrets first, none found).
  Troy WANTS the Mac App Store once his Developer membership is active. Work needed: App Sandbox entitlements,
  music/video folders via open panel + security-scoped bookmarks (also network volumes), media keys via
  MPRemoteCommandCenter only (DONE 2026-10-22: the CGEvent tap is gone), verify hog mode under sandbox,
  mpv/MoltenVK dylibs signed in bundle, App Review. Until then Developer ID + notarization for the .dmg.
- Roadmap Phase 5 PASSED 2026-10-18 (Troy confirmed automatic sync works between CMBA and DDMBA). Roadmap complete:
  - TagBee: Track Studio > TagBee tab = search songs, tick, "Open N in TagBee" (double-click opens one), and a
    "Send to TagBee" menu (song playing / album playing / just open TagBee). Uses `ExternalTagEditor`, which
    re-reads files when TagBee saves. (Embedding TagBee inside MacBee isn't possible: it's a separate app.)
  - Mac-to-Mac sync: Settings > Sync (`MacBee/Sync/`): "Sync with my other Macs" on both Macs; Bonjour service
    `_macbee-sync._tcp` (NSBonjourServices in MacBee-Info.plist, merged via INFOPLIST_FILE); 6-digit code per Mac
    (UserDefaults "networkSyncCode"; codes of other Macs in "networkSyncPeerCodes"); "Sync Now" swaps both ways
    over TCP (length-prefixed JSON). Library logic `Sync/ProfileSync.swift` (tested): songs matched by path below
    the music folder, else artist|title|album|seconds; plays added if not already there (same song, same minute)
    with playCount/lastPlayedAt updated; favorites and higher ratings added; playlists matched by folder path +
    name, created or missing songs appended. Never deletes anything (un-favoriting or removing a playlist song
    doesn't travel). Music files aren't copied. Not done: syncing through Plex.
    - Every Sync Now first shows `SyncChoiceSheet` (Troy, after a first sync surprised him): Combine both Macs
      (default), Make <other> match this Mac (`Mode.sendMine`: the other Mac mirrors), Make this Mac match <other>
      (`takeTheirs`). Mirroring (`mirrorProfile`) deletes the target's playlists/folders and favorites, then merges
      the snapshot; plays are always added. The Mac being changed saves `Library-before-sync-<date>.sqlite` first.
      Older MacBees ignore the mode (combine). Checked after Troy's first sync: CMBA received DDMBA's playlists
      ("First Playlist", folder "Mixesblitzes" > "mix 1") and plays (29 -> 100).
  - Track Studio is a mode like Playlist Studio (Troy): click it to enter, again to leave
    (`AppModel.toggleTrackStudio`, `isInTrackStudio`); STUDIO MODE badge and accent tint; a playlist (or smart
    playlist) clicked in the sidebar becomes the TagBee tab's song source (`trackStudioSourcePlaylistId`,
    "Back to Library"); TagBee actions are buttons under the search box. Sidebar: Track Studio and Playlist Studio
    sit apart under a STUDIOS heading. `AppModel.isPlaylistHighlighted` decides sidebar playlist highlighting.
  - In Track Studio, Music / Collections / Artists / Albums / Search open beside it on the left
    (`AppModel.trackStudioBrowse`, `browsableBesideTrackStudio`; ContentRouter splits with a ColumnResizer,
    @AppStorage "trackStudioWidth"); "Close <page>" gives Track Studio the whole window. Songs, albums, artists or
    playlists dragged onto the TagBee list are added to it (each song once; "Songs dragged here"); Clear List (⌘⌫)
    empties it.
- Macs: "CMBA" = Troy's Coding MacBook Air (this one, Claude works here); "DDMBA" = Daily Driver MacBook Air.
  `Tools/macbee.sh updater` makes /Applications/Update MacBee.app on a Mac (DDMBA didn't have it).
  - Music page: Play History is a 500-pt scroll box (~10 songs). Section order and visibility in Settings >
    General > Music page (drag rows, tick boxes, Reset): `HomeSectionKind`, `PreferencesStore.homeOrder/homeHidden`.
  - Music page buttons (Troy): Recently Played "Clear" and Recently Added "Reset" hide what came before
    (UserDefaults "homeRecentlyPlayedClearedAt" / "homeRecentlyAddedResetAt"; nothing deleted); Play History
    "Reset" (with a warning) deletes the `play` rows only (`deletePlayHistory`; counts and Most Played stay).
    "Library Numbers" is called "Library Stats".
  - Sync and deleted playlists: deleting a playlist/folder logs it (`RemovedPlaylistsLog`, UserDefaults, 90 days);
    snapshots carry `removedPlaylists`; the receiving Mac shows "Deleted on <Mac> … Delete them here too?"
    (RootView alert; "Keep Them" isn't asked again), and a combine never re-creates playlists deleted here.
  - Music page Library block = tinted panel with Settings-level controls: scan, Force Rescan, add folder, drag to
    reorder, pause switches, Plex (account, Automatic/Drive/Plex, Sign In, More… = Settings).
  - Mode color: `Theme.modeTint` / `modeBorder` (accent washes) for the Library panel, Track Studio and Playlist
    Studio (outlined), so modes stand out.
  - "Device Sync" naming (Troy): the Track Studio tab that copies playlists to a player/folder is now **Copy To**;
    **Device Sync** means the Mac-to-Mac sync (Settings > Sync). Menu bar **Sync** menu: Copy To… (Track Studio >
    Copy To, via UserDefaults "tagsSection") and Device Sync… (Settings opened on the Sync tab via "preferencesTab").
  - Mini player went black again: several `MPVVideoView`s can exist during the switch, so each now has a `host`
    ("main"/"mini") and only the one matching `MPVPlayer.activeHost` takes the surface (set to "mini" before the
    mini window shows, back to "main" when it closes). Probe checked: picture shows in the small window.
  - Mini player showed a zoomed-in corner: MPVKit's moltenvk context only measures the drawable on video reconfig,
    so after any view resize mpv kept rendering at the old size. `MPVPlayer.scheduleRefit()` (200 ms after a resize)
    briefly sets `video-aspect-override` to aspect*1.0005 then "no", forcing a reconfig; when paused it waits
    until playback resumes (seek/frame-step don't trigger it while paused). Probe confirmed whole picture.
  - Automatic sync (NetworkSync Mode.automatic, on by default, toggle "Keep my Macs in step automatically"):
    every 20 s, if this Mac's snapshot digest changed since the last sync, it syncs with every peer whose code it
    knows; also when a peer comes online. Requests now carry `senderCode`, so the receiving Mac learns the
    sender's code and can start syncs too. Merge is `ProfileSnapshot.merged(mine:myBase:theirs:theirBase:)`:
    each Mac compares only with its OWN snapshot right after the last sync (SyncBase, App Support/MacBee/Sync/
    <peer>.json, sent along as `Request.base`), so removals carry across but songs one Mac lacks never look
    removed. Applied with `LibraryDatabase.applyProfile` (minimal diff, keeps playlist ids). Video likes sync
    by file/folder name (`VideoLibrary.syncedLikeKeys` / `setSyncedLikes`, unmatched keys kept). Snapshots now
    include favorites/ratings of missing (unplugged) songs. Safety: refuses when either side has no favorites,
    playlists or plays; daily backup Library-before-auto-sync.sqlite. Troy confirmed it works between both Macs.
  - Music (Home) in the sidebar always leaves Track Studio and Playlist Studio (removed from
    `browsableBesideTrackStudio`). Track Studio title stays on one line in a narrow pane.
- Equalizer (2026-10-18, Troy): 16-band EQ + preamp (±12 dB), View > Equalizer… (⌥⌘E, moved from Controls per Troy) or the sliders icon in
  the play bar. Package: `EqualizerSettings`/`EqualizerPreset` (Model/, tested), `EqualizerNode` (Engine/) puts an
  AVAudioUnitEQ between SFB's sourceNode and mainMixer only while active (on and not flat); otherwise it's
  disconnected, so bit-perfect is untouched. Format changes re-wire it via the SFB delegate
  `reconfigureProcessingGraph`. Active EQ = SignalPathStatus issue `.equalizer` + orange "EQ" tag by the badge.
  App: `MacBee/Equalizer/` (EqualizerStore: UserDefaults "equalizer", "equalizerPresets", "equalizerPreset"; per
  Mac). Presets Typical, Punchy, Reduce Treble, Brite, Indie (renamed by Troy from Rock/Soft/Electronic; Flat removed
  from the menu, Troy: same as no EQ; Reset still uses it);
  saved ones listed first in the menu. Window stays in front (WindowLevelSetter). Off by default.
  `macbee-play --eq punchy` (q toggles) tests it from Terminal.
- Song mixes (2026-10-18, Troy): song right-click > "Make Mix from Song" (renamed by Troy) (`PlayerViewModel.startMix`,
  `LibraryDatabase.songMix`: ~1/3 same artist, rest similar artists then same genre, shuffled) keeps going: while
  `mixSeed` is set, `topUpMixIfNeeded` (on `QueueManager.onAdvance` and Next) appends 25 more when <= 3 are left,
  built from the LAST song in the queue (25th, 50th, ...), so the mix is endless and drifts (Troy); any
  other play() ends the mix. "Play More from <artist>" = that song, then the artist's others shuffled.
  If that song is the one playing, it keeps playing and the rest replaces Up Next (`continueOrPlay`), per Troy.
  Playing From (and showCurrentAlbum) in Track Studio opens beside the studio instead of leaving it (Troy).
  Artist page album headers (Albums and songs layout): heart button + "…" menu (`AlbumMoreMenu`: Play Next,
  Add to Queue, Add to Playlist) next to Play.
- Random play (Troy): right-click Artists / Albums / Playlists in the sidebar > dice "Play a Random Artist/Album/
  Playlist" (`RandomPlayMenu`, `AppModel.playRandom*`).
- Continuous play (Troy): Settings > General > Continuous play. `continuousPlay` (default on): when the queue ends
  (engine `.queueFinished` via eventHandler in AppModel), `PlayerViewModel.queueDidFinish` starts an endless mix from
  the last song. `continuousPlayEpisodes` (default on, also a switch on Videos > TV Shows): next episode autoplay.
- Video sorting (Troy): sort menu next to the search box on Movies / TV Shows / Music Videos (`VideoSort.swift`):
  Title, Year, Genre, Date Added (music videos: Title, Artist, Date Added), Ascending/Descending; saved per page in
  UserDefaults "videoSort.<category>".
- Video hang fix (2026-10-18): playing a show gave a beach ball + black picture. Deadlock: mpv's vo thread (holding
  mpv's dispatch lock during reconfig) set `MPVMetalLayer.wantsExtendedDynamicRangeContent`, whose override did
  `DispatchQueue.main.sync`, while the main thread was in `mpv_set_property` (scheduleRefit) waiting for that lock.
  The setter now uses main.async. Never block mpv's threads on the main thread.
- All five roadmap phases built.
- Media keys rule (2026-10-22, APPSTORE_MEDIA_KEYS.md Parts 1-2, Troy's App Store plan): MacBee never intercepts
  media keys. No `CGEvent.tapCreate`, global NSEvent key monitors, `IOHIDManager`, `AXIsProcessTrusted` or
  Accessibility prompt, ever (local monitors inside MacBee's windows are fine). `NowPlayingService` registers with
  MPRemoteCommandCenter / MPNowPlayingInfoCenter like Apple Music; the app that most recently started playing gets
  the keys. While a song is loaded it reports "paused", never "stopped" (the engine stops briefly between songs and
  on rate switches, which could hand the keys away). Removed: MediaKeyTap.swift, the "Media keys always control
  MacBee" setting. Why it "lost to Qobuz": checked with CGGetEventTapList on CMBA, Qobuz installs its own ACTIVE
  event tap on media keys whenever it's open (it has Accessibility permission). Fix is on Troy's side: System
  Settings > Privacy & Security > Accessibility > Qobuz off. Troy tested 2026-10-23: everything passed. Part 4
  (docs/ROADMAP.md wording) done 2026-10-23.
- App Store build (APPSTORE_MEDIA_KEYS.md Part 3, started 2026-10-23, waiting for Troy's test): build configuration
  "AppStore" (target settings: ENABLE_APP_SANDBOX = YES, `MacBee-AppStore.entitlements` = sandbox, user-selected
  read-write, app-scope bookmarks, network client + server, its own keychain group (so it never sees the everyday
  copy's Plex sign-in); compilation condition APPSTORE).
  `Tools/macbee.sh appstore` builds it into ~/Library/Developer/MacBee/DerivedData-AppStore, checks signatures of the
  embedded mpv/MoltenVK frameworks, quits the everyday MacBee and opens it. Its bundle id is
  com.troyhomenchuk.MacBee.appstore, data in ~/Library/Containers/com.troyhomenchuk.MacBee.appstore (fresh library).
  NEVER give a sandboxed build the everyday id com.troyhomenchuk.MacBee: on its first launch macOS MOVED the everyday
  copy's preferences plist into the container (2026-10-23; restored with `defaults import`). Never run both at once.
  Both builds now: `FolderAccess` (MacBeeLibrary/Tagging) keeps security-scoped bookmarks (UserDefaults
  "folderBookmarks") for music folders (`MusicLibrary.addFolder/removeFolder`), video folders and the Copy To device,
  opened at launch and again when a drive mounts. Covers are embedded by MacBee itself (`CoverWriter`, SFBAudioEngine,
  tested) instead of running TagBee's `--set-cover` helper with Process() (not allowed in the sandbox), so Find
  Covers no longer needs TagBee 1.1. Exclusive mode: `acquireHogMode` checks it really got the device and otherwise
  reports "Exclusive mode isn't available..." (sandbox behaviour still to be tested). Users upgrading from a
  non-sandboxed copy with the same id get their settings moved in, so the AppStore build drops video folders and the
  Copy To device that have no bookmark (`forgetFoldersWithoutAccess`). Not done yet: moving Troy's
  existing data into the container (only if he switches his everyday copy), App Store upload/review.
- Record to MiniDisc (2026-10-22, Troy; for recorders without USB): playlist "…" menu, or the button beside
  an MD Mix's capacity bar, opens `RecordToMiniDiscSheet` (`MacBee/MiniDisc/`). `RecordOutSession`: 3 s lead-in,
  then plays the list with a silent gap (2-6 s, UserDefaults "recordOutGap") so the recorder makes a new track per
  song; shuffle/repeat off while running (restored after), end of list doesn't start continuous play
  (`PlayerViewModel.queueFinishedOverride`). Engine: `RecordOutMode` (MacBeeAudio, tested) via
  `setRecordOut`: songs never enqueued gaplessly, gap before each next song, output capped at 48 kHz (MiniDisc
  optical takes 32/44.1/48). "Copy Track Names" copies a numbered title list. "Pause After This Song" (Troy) clears Up
  Next so the list stops when the song ends (phase .paused; also works during the gap: engine `queueDidChange`
  re-plans a scheduled gap start); "Resume Play" plays on from the next song after the lead-in (`runStart`). USB transfer (NetMD) is a separate
  project, MD-deck (see /mnt/project-files/MD-DECK_HANDOFF.md in the Claude project).
- Progress notes: whoever finishes a piece of work updates this Status section and pushes to main, so the other
  Mac (and the next chat) picks up where things stand.
- Defaults Troy chose: start page "Where I left off"; theme "System" (follows macOS dark/light).
- UI rule from Troy: no looping/indeterminate animations (spinners, sliding progress bars); they're distracting.
- Each package has its own README with details.

## Phase 3 — the app shell (done)
Create an Xcode macOS app target named MacBee that uses both local packages. Build:
1. Collapsible sidebar: compact default width, icon-only when collapsed. Items: Music (Home), Artists, Albums,
   Playlists, Tags. Room for nested playlist folders and a "Playlist Studio" button with a tag-editor placeholder.
2. Full-width bottom bar: artwork thumbnail (opens Now Playing later), track info, play/pause/next/previous,
   scrubber with favorite and add-to-playlist icons, output device picker, exclusive-mode toggle,
   bit-perfect badge (uses `SignalPathStatus`), queue-drawer and mini-player buttons (placeholders ok).
3. Basic Artists and Albums views from `MusicLibrary` (album grid with cached covers), double-click to play.
4. A simple play queue (`QueueManager` adopting `PlaybackQueueSource`) so gapless works in the app.
5. Dark theme first, with theme tokens ready for Light / Medium Gray / Dark / Accent.
6. Record plays via `LibraryDatabase.recordPlay` (e.g. after 50% or 4 minutes).

## Later phases
4. (done) Home canvas: library stats, Recently Played, Suggested Mixes, Forgotten Gems, Play History, Scan/Refresh button.
5. (done) Now Playing view (full-screen toggle), queue drawer, mini player.
6. (done) Preferences: themes, monitored folders, Plex sign-in, audio output settings.
7. (done) Playlists, playlist folders, Playlist Studio.
8. (done) Plex and tag-editor hooks.
9. (done) Release: About window, version 1.0, .dmg, performance pass.
