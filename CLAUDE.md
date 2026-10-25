# MacBee — project brief for Claude Code

MacBee is a native macOS music player (Swift / SwiftUI): MusicBee-style bit-perfect playback with a dark,
TIDAL-inspired interface. All original phases (1-9) and the 5-phase post-1.0 roadmap are done.
Full build history, per-feature details and past fixes: `docs/CLAUDE-history.md` (read only when needed).
Design system and original plan: `MACBEE_PLAN.md` (only needed for UI/design work). Each package has its own README.

## About the user
- New to programming and Terminal. Explain briefly, in plain language, no jargon.
- Prefers short answers and no emojis.
- Give exact steps when something must be done by hand; otherwise just do it.
- UI rule: no looping/indeterminate animations (spinners, sliding progress bars).
- Defaults Troy chose: start page "Where I left off"; theme "System".

## Decisions already made
- Audio engine: SFBAudioEngine (~> 0.14.0), wrapped by our `PlaybackEngine` protocol. Video: libmpv via MPVKit (pinned 1.1.0-n9.0.2).
- Formats: FLAC, ALAC, WAV, AIFF, MP3, AAC, DSD (.dsf; DoP or DSD64->PCM default). Minimum macOS 14.
- Two builds (Troy, 2026-10-23): everyday = direct download, no sandbox; "AppStore" configuration = sandboxed, for the Mac App Store.
- Exclusive (hog) mode off by default. Volume: hardware by default; software volume flagged "not bit-perfect" below 100%.
- Music on network drive `/Volumes/2 Set Music` (~9,500 tracks); more folders can be added. Tracks load fully into memory before playing on network drives.
- No external DAC: tests target "MacBook Air Speakers" (the "BoomAudio" output adds effects).
- Architecture: MVVM, small files, no giant single-file dumps.
- Signing: automatic, Troy's team DA9YJ36D24 ("Apple Development"), `MacBee.entitlements` (Keychain Sharing). Paid developer membership active since 2026-10-19. Never go back to ad-hoc or self-signed. If a build gets a 7-day profile, delete ~/Library/Developer/Xcode/UserData/Provisioning Profiles/* and rebuild.
- Virtual output devices (BoomAudio, Loopback, BlackHole) are never switched in sample rate or bit depth (it made Boom 3D produce loud noise); they show "not bit-perfect".

## Rules learned the hard way
- Media keys: never intercept them. No `CGEvent.tapCreate`, global NSEvent key monitors, `IOHIDManager`, `AXIsProcessTrusted` or Accessibility prompt (local monitors inside MacBee's windows are fine). Use MPRemoteCommandCenter / MPNowPlayingInfoCenter; while a song is loaded report "paused", never "stopped".
- Video: don't use SwiftUI `VideoPlayer` (crashes on macOS 26). Never block mpv's threads on the main thread (deadlock). Only one `MPVVideoView` host takes the mpv surface (`MPVPlayer.activeHost`).
- Never give the sandboxed AppStore build the everyday bundle id `com.troyhomenchuk.MacBee` (it moved the everyday preferences into the container). AppStore id is `com.troyhomenchuk.MacBee.appstore`. Never run both at once.
- Trash only via FileManager.trashItem; permanent delete only after a second confirmation on drives without a Trash.
- Sync never deletes without the user's choice; every mirror saves a `Library-before-sync-<date>.sqlite` backup first. DB migrations back up the DB first.
- Naming: sidebar "Media" = `.home`; "Track Studio" = `.tags`; "Copy To" = copy playlists to a device; "Device Sync" = Mac-to-Mac sync (Settings > Sync); Favorites = `.topRated`.

## Where the project lives and how to build
- Project at `~/Projects/MacBee` on each Mac (not iCloud), private-then-public GitHub repo. Troy uses two MacBook Airs, never both at once: "CMBA" = Coding MacBook Air (Claude works here), "DDMBA" = Daily Driver.
- Start of session: `git pull`. After finishing work: commit and `git push`, and say plainly "saved and sent to GitHub". Chats don't sync between Macs; this file carries the context, so keep it current (add detail to `docs/CLAUDE-history.md`, keep this file short).
- Build files never go inside the project folder. Always use `Tools/macbee.sh`: `build`, `test`, `run`, `install` (optimized copy to /Applications/MacBee.app), `update` (git pull + install), `updater`, `dmg`, `release [version]`, `appstore` (sandboxed build). Everything builds into `~/Library/Developer/MacBee`; for `swift run`/`swift test` add `--scratch-path ~/Library/Developer/MacBee/<PackageName>`.
- Per Mac (not synced): music database and play history in `~/Library/Application Support/MacBee/`.
- Releases: `Tools/macbee.sh release` needs `gh` (`~/.local/bin/gh`, signed in once per Mac).

## Status (2026-10-24)
- Done: library, player, playlists/Studios, Plex, TagBee hook, videos (mpv), duplicates, Copy To, Mac-to-Mac sync, equalizer, mixes, lyrics, Record to MiniDisc, media-keys rule (tested OK 2026-10-23).
- In progress: Mac App Store build (`appstore` configuration). Sandbox, folder bookmarks (`FolderAccess`), in-app cover embedding and exclusive-mode break during video are done; folders and exclusive mode passed Troy's first test.
- App Store prep done (2026-10-24): privacy manifest, encryption answer, LGPL credit for mpv/FFmpeg in About.
- Not done: moving Troy's existing data into the container (only if he switches his everyday copy), App Store upload and review.
