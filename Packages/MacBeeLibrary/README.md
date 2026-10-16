# MacBeeLibrary (Phase 2)

The music library for MacBee: finds your music, reads tags and cover art, stores everything
in a local database, and keeps it up to date. No UI yet; the app (Phase 3) uses `MusicLibrary`.

## Try it

The project is in iCloud Drive, so keep build files out of it: add `--scratch-path ~/Library/Developer/MacBee/<PackageName>`
to `swift test` / `swift run` (or use `Tools/macbee.sh test` from the project folder).

```sh
cd "$HOME/Library/Mobile Documents/com~apple~CloudDocs/CLAUDE PROJECTS/MacBee/Packages/MacBeeLibrary"
swift test
swift run -c release macbee-library add "/Volumes/2 Set Music"
swift run -c release macbee-library stats
swift run -c release macbee-library albums 20
swift run -c release macbee-library search bjork
```

Other commands: `scan` (check for changes), `folders`, `artists`, `watch` (stay running and
rescan when things change), `remove <folder>`.

The library is stored in `~/Library/Application Support/MacBee/` (database + cover cache).
The app will use the same files, so the first full scan only happens once.

## How it works

| Folder | Purpose |
|---|---|
| `Model/` | Track, folder, album/artist summaries; grouping rules (`LibraryKeys`) |
| `Database/` | SQLite via GRDB: schema, queries (stats, albums, artists, search, history), scan writes |
| `Scanning/` | Finds files, decides what changed (`ScanPlanner`), reads tags, caches cover art |
| `Monitoring/` | Watches folders: file changes, drives mounting, and a routine check every 30 minutes |
| `MusicLibrary.swift` | The one object the app talks to |

## Network drive safety

- Drive not mounted: the scan changes nothing, and the library stays as it was.
- Files that disappear are flagged "missing" and hidden, not deleted, so play counts survive.
- A file moved or renamed keeps its play history (matched by size, title and length).
- If a folder suddenly looks empty, nothing is marked missing.
- Only new or changed files have their tags read; later scans just compare sizes and dates.
- Changes made from another computer are picked up by the 30-minute check, or right away with `scan`.
- Cover art is copied to a local cache, so it shows instantly even when the drive is slow.

## Albums and artists

Albums are grouped by album artist + album title, ignoring case and accents ("Björk" = "bjork").
Missing album artist falls back to the track artist, or "Various Artists" for compilations.
Untagged files use their folder name as the album.
