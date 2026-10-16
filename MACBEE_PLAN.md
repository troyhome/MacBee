# MacBee — Full Project Plan

This is the complete plan for MacBee: what it is, what has been decided, what exists, and what every
remaining phase must deliver. Read it before starting any phase. When a phase is finished, update the
Status section of CLAUDE.md (and tick the phase here).

---

## 1. What MacBee is

A native macOS music player for a local/network FLAC library. It combines MusicBee's audiophile
playback (bit-perfect output, gapless, automatic DAC sample-rate switching) with a modern, dark,
TIDAL-inspired interface.

## 2. About the user (how to work with him)

- Troy is new to programming, Xcode and Terminal. Explain briefly, in plain language, no jargon.
- Prefers short answers and no emojis.
- When he must do something by hand, give exact steps (what to click, what to paste).
  Otherwise do it yourself: build, run tests, fix errors.
- He tests by listening and by using the app. Tell him exactly what to try and what "good" looks like.
- Music: ~9,500 tracks (growing), mostly FLAC, some hi-res (24/96 etc.), on a network drive
  mounted at `/Volumes/2 Set Music`. Folder style: `Artist/Year - Album/NN Title.flac`.
- Hardware today: MacBook Air speakers (max 96 kHz). No external DAC yet, but the app must be ready
  for one. A "BoomAudio" output (Boom 3D app) exists; it adds effects, so it is never bit-perfect.

## 3. Decisions (do not change without asking)

| Topic | Decision |
|---|---|
| Language/UI | Swift + SwiftUI (AppKit where SwiftUI falls short). MVVM. |
| Minimum OS | macOS 14 Sonoma |
| Distribution | Direct download, not the App Store (no sandbox). App name in Applications: **MacBee** |
| Audio engine | SFBAudioEngine (~> 0.14.0) behind our `PlaybackEngine` protocol |
| Formats | FLAC, ALAC, WAV, AIFF, MP3, AAC, DSD (.dsf). DSD as DoP (bit-perfect, DAC must support) or DSD64→PCM (default) |
| Exclusive (hog) mode | Off by default; one click to turn on, in Preferences and in the bottom bar |
| Volume | Hardware (DAC) volume by default. Optional software volume, clearly flagged "not bit-perfect" below 100% |
| Network playback | Current and next track loaded fully into memory before playing (fixed real dropouts) |
| Database | SQLite via GRDB, stored in `~/Library/Application Support/MacBee/` |
| Code style | Small focused files, one view/viewmodel per file. No giant single-file dumps. Build and test step by step |
| Extensibility | Clean placeholder protocols/views for a future external tag editor and Plex connection |

## 4. What exists

```
MacBee/
├─ CLAUDE.md, MACBEE_PLAN.md
├─ MacBee.xcodeproj, MacBee/   Phase 3 — the app (done)
├─ Tools/make-icon.swift      draws the app icon
└─ Packages/
   ├─ MacBeeAudio/     Phase 1 — playback engine (done, tested by ear)
   └─ MacBeeLibrary/   Phase 2 — library (done, verified with a full scan)
```

### MacBeeAudio (key types)
- `PlaybackEngine` protocol / `SFBPlaybackEngine` (@Observable, @MainActor): `play(url)`, pause/resume,
  `seek`, `stop`, `setVolume`, `apply(OutputSettings)`, `availableOutputDevices()`, `shutdown()`.
  Observable: `state`, `currentTrack`, `currentFormat`, `progress`, `signalPath`, `outputDevice`,
  `deviceSampleRate`, `deviceBitDepth`, `volume`, `hardwareVolumeAvailable`, `lastError`.
- `PlaybackQueueSource` protocol: `track(after:)`, `engineDidAdvance(to:)`. The engine pre-loads the
  next track for gapless playback. Call `queueDidChange()` after reorder/shuffle/removal.
- `OutputSettings`: deviceUID, exclusiveMode, volumeMode, softwareVolume, dsdMode, preferHighestBitDepth.
- `SignalPathStatus`: `isBitPerfect`, issues (resampled, software volume, bit depth reduced, DSD→PCM),
  notes (shared mode, lossy source), `summaryLines` for a tooltip.
- `AudioDeviceManager`, `SampleRatePolicy`, `DecoderFactory.supportedExtensions`.
- Test tool: `swift run -c release macbee-play --device "MacBook Air Speakers" files...`

### MacBeeLibrary (key types)
- `MusicLibrary` (@Observable, @MainActor): `start()`, `addFolder`, `removeFolder`, `scanAll()`,
  `cancelScan()`, `artworkURL(for:)`. Observable: `folders` (with online/network state), `stats`,
  `scanProgress`, `lastReports`, `revision` (bumps when contents change; reload lists then).
- `LibraryDatabase` queries: `stats()`, `albums(sortedBy:artistKey:limit:)`, `artists()`,
  `tracks(inAlbum:)`, `track(id:)`, `search(_:)`, `recentlyPlayedTracks()`, `recordPlay(trackId:)`,
  `setFavorite(trackId:_:)`, folders.
- Tables: `folder`, `track` (tags, format, albumKey/artistKey, playCount, lastPlayedAt, isFavorite,
  rating, isMissing, dateAdded), `artwork`, `play` (trackId, playedAt).
- Network safety: offline drive changes nothing; vanished files are flagged missing (hidden, not
  deleted); moved files keep history; empty-looking folder skips removals; 30-minute routine rescan,
  rescan on drive mount, FSEvents for local changes. Covers cached locally as JPEG (max 1200 px).
- Test tool: `swift run -c release macbee-library add|scan|stats|folders|albums|artists|search|watch|remove`

---

## 5. Design system (applies to every screen)

**Look:** sleek, dark, neutral, content-first like TIDAL. Album art is the hero. Generous spacing,
quiet chrome, no heavy borders. Smooth, subtle micro-interactions.

**Themes:** Dark (default), Medium Gray, Light, plus an Accent color choice. Implement as theme tokens
(e.g. `Theme.background`, `surface`, `surfaceRaised`, `textPrimary`, `textSecondary`, `accent`,
`divider`, `badgeBitPerfect`) in one place. No hard-coded colors in views.

Suggested Dark values (adjust by eye):
- background #0E0E10, surface #17171A, raised #202024, divider #2A2A2F
- text primary #F2F2F5, secondary #9A9AA3, accent default a cool teal/cyan (user-selectable)

**Type:** system font (SF Pro). Clear hierarchy: large bold section titles, medium album titles,
small secondary metadata.

**Interactions:**
- Album cards: rounded corners, slight scale-up and shadow on hover, a play button fades in over the cover.
- Rows highlight on hover; double-click plays; right-click menu (Play, Play Next, Add to Queue,
  Add to Playlist, Favorite, Show in Finder, Go to Artist/Album).
- Animations 150–250 ms, ease-out. Sidebar collapse animates.
- Keyboard: Space play/pause, ⌘→ / ⌘← next/previous, ⌘F search, ⌘, Preferences.
- Media keys and Control Center "Now Playing" (MPNowPlayingInfoCenter + MPRemoteCommandCenter).

**Formats shown:** a small quality badge where useful, e.g. "FLAC 24/96", "Hi-Res", "DSD64".
A "Bit-Perfect" badge in the bottom bar, green when bit-perfect; tooltip shows `summaryLines`.

---

## 6. Phases

### Phase 1 — Audio engine  ✅ done
### Phase 2 — Library  ✅ done (verified: builds, tests pass, full scan of "2 Set Music", albums/covers look right)

### Phase 3 — App shell  ✅ done
Create the Xcode macOS app target **MacBee** using both local packages.

1. **App structure:** `AppEnvironment` creates one `SFBPlaybackEngine`, one `MusicLibrary`, one
   `QueueManager`, one `PreferencesStore` and shares them via the SwiftUI environment.
   On quit: `engine.shutdown()` (releases exclusive mode).
2. **Collapsible sidebar:** compact default width (~200 pt); collapses to icons only (~60 pt) with a
   toggle. Items: Music (Home), Artists, Albums, Playlists, Tags. Below: a Playlists section that
   supports nested folders (placeholder list for now) and a **Playlist Studio** button (opens a
   placeholder view with an empty slot labelled for the future tag editor). Search field at top.
3. **Full-width bottom bar** (always visible):
   - Left: artwork thumbnail (click → Now Playing, Phase 5), title, artist, quality badge.
   - Center: shuffle, previous, play/pause, next, repeat; scrubber with elapsed/remaining time;
     favorite (heart) and add-to-playlist icons next to it.
   - Right: Bit-Perfect badge, exclusive-mode toggle, output device picker (lists devices, marks the
     current one, shows supported rates), volume slider (hardware or software per settings; disabled
     with a note if the device has no hardware volume), queue-drawer button, mini-player button
     (placeholders until Phase 5).
4. **Artists view:** list/grid of album artists; selecting one shows their albums.
5. **Albums view:** grid of album covers (lazy, fast with ~1,000 albums), sort by Artist/Title/Year/
   Recently Added. Album detail: big cover, title, artist, year, format, track list
   (disc/track, title, duration, format). Double-click a track plays the album from that track.
6. **QueueManager** (adopts `PlaybackQueueSource`): play album from track N, play next, add to queue,
   previous (restart track if > 3 s in), shuffle, repeat off/all/one. Gapless works through the engine.
7. **Play counting:** call `recordPlay` once per play when ≥ 50% or ≥ 4 minutes have been heard.
8. **Settings persistence:** `PreferencesStore` saves `OutputSettings`, theme, sidebar state, window
   size (UserDefaults or a small JSON file).
9. Dark theme via tokens; other themes can wait until Phase 6.

**Done when:** the app launches, shows the library, plays albums gaplessly, the bottom bar controls
work, the device picker switches output, and the Bit-Perfect badge is correct.

### Phase 4 — Home screen (Music)  ✅ done
1. **Stats cards:** Artists, Albums, Tracks, Total time (e.g. "27 days 4 h"). Update after scans.
2. **Recently Played:** horizontal row of album cards, newest first (from `play`/lastPlayedAt).
3. **Recently Added:** horizontal row of newest albums (dateAdded).
4. **Suggested Mixes:** 4–6 auto-generated mixes shown as cards (collage of 4 covers + name):
   e.g. "Most Played", one per top genre, one per decade ("1990s"), "Hi-Res Picks" (≥ 88.2 kHz),
   "Favorites". Clicking plays/shuffles the mix. Regenerate daily or on scan.
5. **Forgotten Gems:** albums/tracks played ≥ 3 times but not in 6+ months, plus favorites not played
   in 3+ months. Row of cards.
6. **Play History:** list of plays, newest first, grouped by day (Today, Yesterday, date), with time,
   cover thumbnail, title, artist. Paged/limited for speed.
7. **Scan/Refresh Library** button: runs `scanAll()`, shows progress (phase + count), last scan time,
   and each folder's status (online/offline, network). Shows a short summary after a scan
   (added/updated/missing).
8. Empty states: friendly messages when there is no history yet or no folders added
   (with an "Add Music Folder" button).

Add database queries needed (history grouped by day, forgotten gems, genre/decade mixes) to
MacBeeLibrary with unit tests.

### Phase 5 — Now Playing, queue drawer, mini player  ✅ done
1. **Now Playing view:** opened from the bottom-bar artwork. Large cover, blurred cover background,
   title/artist/album, full format line ("FLAC 24-bit / 96 kHz → MacBook Air Speakers 96 kHz,
   Bit-Perfect"), scrubber, controls, favorite. Toggle to true full screen. Esc closes.
   Placeholder area for lyrics (future).
2. **Queue drawer:** slides in from the right. Shows Now Playing, Up Next (drag to reorder, swipe/
   delete to remove, clear), and recently played in this session. Calls `queueDidChange()` on edits.
3. **Mini player:** small floating window (always-on-top option): cover, title/artist, play/pause,
   next/previous, scrubber. Toggle from the bottom bar; restores the main window when closed.
4. Media keys, Control Center "Now Playing", dock menu (play/pause, next).

### Phase 6 — Preferences (⌘,)  ✅ done
Tabs:
1. **General:** launch behaviour, show quality badges, play-count threshold.
2. **Appearance:** Theme (System — the default, Light, Medium Gray, Dark), Accent color picker, sidebar default width.
3. **Library:** monitored folders list (add with a folder picker, remove, show online/offline,
   network/local, last scan), "Scan Now", routine-check interval (off / 15 / 30 / 60 min),
   "Show missing files" toggle with an option to clean them up.
4. **Audio:** output device, exclusive mode, volume mode (hardware/software) with an explanation of
   bit-perfect impact, DSD mode (PCM conversion vs DoP, with a warning that DoP needs DAC support),
   prefer highest bit depth, load-into-memory toggle (on by default).
5. **Plex:** sign-in placeholder (server URL, sign-in button, status) wired to a `PlexService`
   protocol stub. No real networking yet.
6. **Tag Editor:** placeholder for choosing/launching the future external tag editor.

### Phase 7 — Playlists and Playlist Studio  ✅ done (smart playlists not done)
1. Database: `playlist` (id, name, parentFolderId, isFolder, sortOrder, createdAt) and
   `playlistItem` (playlistId, trackId, position). Migration `v2` in MacBeeLibrary, with tests.
2. Sidebar: nested playlist folders (disclosure triangles), drag tracks/albums onto a playlist,
   drag to reorder playlists and move them between folders, rename, delete (with confirm).
3. Playlist view: cover collage, name, track count/duration, track list (reorder by drag), play/shuffle.
4. Add-to-playlist from the bottom bar icon, right-click menus and drag and drop.
5. Import/export M3U/M3U8 (relative paths when possible).
6. **Playlist Studio:** a focused workspace: library browser on the left, playlist being built on the
   right, filters (genre, year range, format, rating, play count). Includes the reserved **tag editor
   slot** panel (placeholder view + `TagEditorService` protocol) for the future tool.
7. Smart playlists (optional if time allows): rule-based (e.g. genre is Jazz and year < 1970).

### Phase 8 — Plex and tag editor hooks  🔨 built, waiting for Troy's check (Plex = away-from-home route to the same library; tag editor = TagBee)
1. `PlexService` protocol with a real implementation: sign in (plex.tv PIN flow), list servers and
   music libraries, browse artists/albums/tracks, stream URLs. Show Plex as a separate source in the
   sidebar. Playback of Plex tracks may need a streaming path in the engine (cannot be bit-perfect
   guaranteed if transcoded; request original/direct play).
2. `TagEditorService` protocol: open selected tracks in an external tag editor (app chosen in
   Preferences) and rescan those files when it reports changes or when files change on disk.
3. Keep both behind protocols so they can be swapped or removed.

### Phase 9 — Release (suggested)
1. App icon, About window, version number.
2. Build a signed, notarized `.app` (requires an Apple Developer account; otherwise explain the
   "right-click → Open" first-launch step) packaged as a `.dmg` with drag-to-Applications.
3. Simple update check (optional), crash-free first-run (no folders yet → onboarding to add one).
4. Performance pass with the full library: launch time, scrolling the album grid, memory use.

---

## 7. Testing approach
- Logic (queries, grouping, queue rules, mixes) gets unit tests in the packages.
- After each phase, build the app and give Troy a short checklist of things to try.
- Keep `macbee-play` and `macbee-library` working; they help debug without the UI.

## 8. Open notes
- Gapless across a sample-rate change is impossible (DAC re-locks); same-rate tracks are gapless.
- DSD→PCM handles DSD64 only; DSD128/256 need DoP.
- Changes made to the network drive from another computer are seen by the routine rescan, not instantly.
