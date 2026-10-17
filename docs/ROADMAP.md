# MacBee Development Roadmap (after 1.0)

Troy's roadmap, received 2026-10-17. Work goes one phase at a time. Phase status is tracked in
`CLAUDE.md` (Status section) so either Mac picks up where things stand.

## Phase Progression Rules
1. Do not start a subsequent phase until Troy confirms the current phase passes its Exit Verification Gate
   (zero compiler errors, all tests pass, and manual smoke tests succeed).
2. Write clean, modular Swift/SwiftUI code.

## Phase 1: UI Geometry, System Controls & Navigation Layout
- Search Results Clipping: Add top content insets/padding to the search view so the top artist result is not
  obscured under the navigation toolbar.
- Playbar Clean-up: Remove audio format and bitrate labels from the bottom-left track metadata block (leave only
  thumbnail artwork, title, artist, album/EP). Ensure audio format/bitrate indicators remain exclusively on the
  right side next to the output device selector.
- Album Detail View Header: Add header action controls matching Apple Music standards: "Play Next",
  "Play Later", "Add to Playlist...", and "Favorite".
- Collection View: Add a "Collection" navigation entry in the primary sidebar that takes over the main canvas,
  containing a segmented sub-view for Playlists, Albums, Tracks, Videos, and Saved Mixes.
- Sidebar Library Status: Place a subtle status element directly beneath "Playlist Studio" indicating the active
  source (Local vs. Plex) and a manual "Force Rescan" button.
- Preferences Hierarchy: Relocate all Plex server settings under the "Library" preferences tab.
- Hover Navigation for Carousels: Add hover-triggered left and right navigation arrows to all horizontal scroll
  containers to allow mouse navigation without horizontal wheel or trackpad gestures.
- System Media Dominance: Configure MPRemoteCommandCenter and MPNowPlayingInfoCenter to intercept system media
  keys upon playback initiation, preventing background applications (Apple Music, Spotify) from receiving
  playback events.
- Gesture Navigation: Add a global two-finger secondary tap/click gesture recognizer across the interface to
  trigger skip-to-next-track.

## Phase 2: Multi-Source Library Prioritization, Deduplication & Artist Filtering
- Reorderable Storage Sources: In Library Settings > Monitored Folders, support multiple local and network
  storage paths. Make folder rows reorderable via drag-and-drop to define source priority.
- Source Pausing: Add a toggle switch beside each monitored directory to pause/exclude it from the active library
  index without removing the saved path.
- Automatic Source Failover: When initiating playback, if a file's primary location is unreachable,
  automatically resolve playback from secondary prioritized paths containing the matching audio file.
- Deduplication Engine: Identify duplicate tracks using metadata fingerprinting (Artist + Track Title + Album +
  Duration within a 2-second delta). Merge duplicates under a single visible track entry.
- Compilation Artist Exclusion: Add a toggle in Preferences: "Hide compilation-only artists from Artists view".
  Filter out artists who only appear as guest features on compilation albums unless they have at least one
  standalone album where they are the primary album artist.
- Home View Source Badge: Display an active source badge ("Local Library" or "Plex Server") on the Home view with
  an immediate toggle switch to flip between library views.

## Phase 3: Playlist Studio, Smart Mixes & MiniDisc Budgeting
- Playlist Import & Export: Add full import and export support for .m3u and .m3u8 playlist files (relative and
  absolute system file paths).
- Suggested Mix Refresh & Persistence: On the Home view, add a "Refresh Suggestions" button to rebuild procedural
  mixes. Add an action on each suggested mix card to "Save to Saved Mixes".
- Smart Playlist Engine (Playlist Studio): Implement rule-driven dynamic playlist generators:
  - "Recently Added": Auto-populated with the last 50 added tracks.
  - "Most Played": Auto-populated with the top 100 tracks by play count.
  - "Top Rated": Auto-populated with the top 150 tracks marked as favorites.
- MiniDisc Capacity Mixers:
  - Add two specialized capacity-limited templates: "74min MD Mix" and "80min MD Mix".
  - Auto-fill tracks using user-defined criteria strictly bounded by the total running time (74:00 or 80:00).
  - Capacity Status Bar: Show total running duration vs. capacity limit.
  - Alert Warnings: Flag an "Overtime" warning if the track duration exceeds the limit. Display an "Underfill"
    warning if unused remaining capacity exceeds 7 minutes.

## Phase 4: External DAP / Storage Sync & Lyrics System
- Portable DAP / External Drive Sync: Add a dedicated sync tool targeting connected mass-storage devices or
  network paths. Sync individual playlists or smart mixes. Implement delta synchronization (copy only
  new/modified files formatted as Artist/Album/## - Track.ext, export .m3u, prune deleted tracks).
- Lyrics Display Engine: Add a synchronized and unsynchronized lyrics viewer.
  - Priority 1: Read unsynchronized text embedded directly in file metadata.
  - Priority 2: Detect external .lrc files sharing the track's base filename in the same directory and scroll in
    real-time.

## Phase 5: TagBee Integration & Multi-Client Network Sync
- TagBee Utility Hook: Connect the "Tags" item in the left navigation sidebar to launch/embed the pre-existing
  TagBee utility. Pass selected track URLs to the tagger.
- Local Network Profile Sync: Design a lightweight local network synchronization bridge to sync playlists, play
  counts, ratings, and play history between two MacBee instances on the same network (or through Plex API).
