# MacBeeAudio (Phase 1)

The playback engine for MacBee, as a standalone Swift package. No UI yet.
The app (Phase 3+) will add it as a local package and talk to it through the `PlaybackEngine` protocol.

## Try it

The project is in iCloud Drive, so keep build files out of it: add `--scratch-path ~/Library/Developer/MacBee/<PackageName>`
to `swift test` / `swift run` (or use `Tools/macbee.sh test` from the project folder).

Requires Xcode 15.3+ on macOS 14+. In Terminal:

```sh
cd "$HOME/Library/Mobile Documents/com~apple~CloudDocs/CLAUDE PROJECTS/MacBee/Packages/MacBeeAudio"
swift test                                  # unit tests
swift run macbee-play --list-devices        # see your DACs and their supported rates
swift run macbee-play ~/Music/a.flac ~/Music/b.flac
swift run macbee-play --exclusive --device "DAC name" track1.flac track2.flac
swift run macbee-play --dop album/*.dsf     # only if your DAC supports DoP
```

While playing, type `p` + Return (pause/resume), `n` (next), `e` (jump to the last 10 seconds), `+` / `-` (volume), `s` (quit).

Add `-c release` after `swift run` for listening tests; it builds an optimized version, like the final app.
The first build downloads SFBAudioEngine and its codecs, so it takes a few minutes.

To work in Xcode instead: File > Open > choose `Package.swift`.

## What to check

- Each track prints its format, the DAC rate and bit depth, and whether the path is bit-perfect.
- Two consecutive tracks from the same album should play with no gap.
- A 44.1 kHz track followed by a 96 kHz one should switch the DAC (short pause there is expected).
- `--exclusive`: other apps' sound should be blocked while MacBee plays.

## Files

| Folder | Purpose |
|---|---|
| `Model/` | Plain value types: format info, settings, signal-path check, events, errors |
| `Device/` | CoreAudio device control: list devices, sample rate, bit depth, exclusive mode, hardware volume |
| `Decoding/` | Picks the right decoder per file (incl. DSD as DoP or PCM) |
| `Engine/` | `PlaybackEngine` protocol and the SFBAudioEngine-based implementation |
| `MacBeePlayCLI/` | Terminal test player |

## Known limits (for now)

- DSD to PCM conversion supports DSD64 only. DSD128/256 need DoP.
- A sample-rate change between tracks can't be gapless (the DAC has to re-lock); same-rate tracks are.
- Each track (and the next one) is loaded fully into memory before it plays, so network drives can't cause dropouts. Files over 1.5 GB are read directly.
- Software volume uses the output unit's gain. It is flagged as not bit-perfect below 100%.
