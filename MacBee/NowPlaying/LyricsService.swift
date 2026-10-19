import Foundation
import MacBeeLibrary
import Observation

/// Finds lyrics online for songs that have none (Settings > General > Lyrics, on by default). When a song
/// starts, its lyrics are looked up at LRCLIB and saved as an .lrc file next to the song (or, if that folder
/// can't be written to, in Application Support > MacBee > Lyrics), so the lyrics panel shows them from then on,
/// on every Mac that reads the same music folder.
@MainActor
@Observable
final class LyricsService {
    /// Goes up when lyrics were saved for a song, so open lyrics panels load them.
    private(set) var savedCount = 0
    private(set) var searchingPath: String?

    /// Songs looked up without luck, with when, so they're only tried again after a couple of weeks.
    @ObservationIgnored private var misses: [String: Date] =
        UserDefaults.standard.dictionary(forKey: "lyricsNotFound") as? [String: Date] ?? [:]

    init() {
        LyricsReader.savedCopiesFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee/Lyrics")
    }

    /// Looks up and saves lyrics for `track` if it has none yet.
    func fill(_ track: Track) async {
        let path = track.path
        if let missed = misses[path], Date().timeIntervalSince(missed) < 14 * 86_400 { return }
        let song = track
        let has = await Task.detached(priority: .utility) { LyricsReader.lyrics(for: song) != nil }.value
        guard !has, FileManager.default.fileExists(atPath: path) else { return }

        searchingPath = path
        defer { if searchingPath == path { searchingPath = nil } }
        let outcome: LyricsFinder.Outcome
        do {
            outcome = try await LyricsFinder.find(artist: track.artist ?? track.displayArtist, title: track.displayTitle,
                                                  album: track.displayAlbum, duration: track.duration)
        } catch {
            return // offline or LRCLIB unreachable: try again next time the song plays
        }
        guard case let .found(found) = outcome else {
            misses[path] = Date()
            UserDefaults.standard.set(misses, forKey: "lyricsNotFound")
            return
        }
        let saved = await Task.detached(priority: .utility) { Self.save(found.text, for: URL(fileURLWithPath: path)) }.value
        if saved { savedCount += 1 }
    }

    /// Next to the song first; if that folder is read-only, MacBee's own Lyrics folder.
    nonisolated private static func save(_ text: String, for song: URL) -> Bool {
        let data = Data((text + "\n").utf8)
        let beside = song.deletingPathExtension().appendingPathExtension("lrc")
        if (try? data.write(to: beside, options: .atomic)) != nil { return true }
        guard let copy = LyricsReader.savedCopyURL(for: song) else { return false }
        try? FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: copy, options: .atomic)) != nil
    }
}
