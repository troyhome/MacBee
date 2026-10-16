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
- Minimum macOS 14 Sonoma. Direct download, not the App Store (no sandbox).
- Exclusive (hog) mode: off by default, one-click toggle in settings and the play bar.
- Volume: hardware (DAC) volume by default; optional software volume, flagged "not bit-perfect" below 100%.
- Music lives on a network drive mounted at `/Volumes/2 Set Music` (~9,500 tracks, growing). More folders can be added later.
- Network playback: each track and the next one are loaded fully into memory before playing (fixed real dropouts).
- The Mac currently has no external DAC; the "BoomAudio" output (Boom 3D app) adds effects, so tests target "MacBook Air Speakers".
- Code signing: the app is signed with Troy's self-signed "MacBee Local Signing" certificate (Keychain), so macOS
  remembers permissions (network volume access) across rebuilds. Don't switch back to ad-hoc ("-") signing.
  His "Apple Development" certificate exists but fails to sign (errSecInternalComponent); revisit in Phase 9.
  The certificate on Troy's first MacBook Air expires 2027-10-16 (made with the 1-year default). New ones: Keychain
  Access > Certificate Assistant > Create a Certificate, Name "MacBee Local Signing", Self Signed Root, Code Signing,
  "Let me override defaults", validity 3650 days, other pages left as they are.
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
  re-run it after changes he should get).
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
- Phase 7 DONE (checked by Troy): playlists + nested folders (DB migration v2; `LibraryDatabase+Playlists.swift`,
  `M3UPlaylist`, tests in `PlaylistTests`), app code in `MacBee/Playlists/` (PlaylistStore, sidebar tree, pages,
  drag payloads as "macbee:..." strings), Add to Playlist menus in `MacBee/Menus/`, Playlist Studio in
  `MacBee/Studio/` with a reserved TagEditorSlot. Smart playlists (optional) not done.
  Studio mode (Troy's design): clicking Playlist Studio enters it, clicking it again returns to where you were;
  Music/Artists/Albums/Search leave it. In studio mode a sidebar playlist click (or dropping a playlist on the
  middle pane) shows that playlist's songs there ("Back to Library" returns); dropping a playlist on the right pane
  adds all its songs. Search-in checkboxes (Artist, Album, Song title; none = everything). Panes tinted with the accent.
- Phase 8 BUILT, NEEDS TROY'S CHECK:
  - Tag editor = TagBee (`/Applications/TagBee.app`, default when nothing valid is chosen). `ExternalTagEditor`
    (MacBee/Services) opens songs there and watches the files for ~1 hour, re-reading them via
    `MusicLibrary.refreshFiles` when saved. "Edit Tags in TagBee…" in song/album menus and Playlist Studio.
  - Plex = an automatic away-from-home route to the SAME library (Troy's Plex serves the 2 Set Music files), not a
    second library. `MacBee/Plex/` (PlexAPI, PlexConnection: PIN sign-in via browser, token in Keychain, servers,
    connection order home > internet > relay), `PlexMatcher` + `plexLink` table (DB v4) pair Plex files with library
    songs by path below the music folder. `PlaybackRouter` (MacBee/Playback) picks drive vs Plex per song
    (Preferences > Plex: Automatic / Always drive / Always Plex), downloads originals to
    ~/Library/Caches/MacBee/Plex (3 GB limit) so playback stays bit-perfect. Play bar shows "PLEX".
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
8. (built, checking) Plex and tag-editor hooks.
