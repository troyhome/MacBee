import Foundation
import SFBAudioEngine

/// A song's lyrics: plain text, or lines with times (from an .lrc file, or embedded text in LRC format).
public enum Lyrics: Equatable, Sendable {
    case plain(String)
    case timed([TimedLine])

    public struct TimedLine: Equatable, Sendable, Identifiable {
        public var time: Double
        public var text: String
        public var id: Double { time }
        public init(time: Double, text: String) {
            self.time = time
            self.text = text
        }
    }

    /// Index of the line being sung at `time` (nil before the first line).
    public static func currentLine(in lines: [TimedLine], at time: Double) -> Int? {
        var current: Int?
        for (index, line) in lines.enumerated() {
            if line.time <= time + 0.05 { current = index } else { break }
        }
        return current
    }
}

/// Finds a song's lyrics (roadmap Phase 4): the text embedded in the file's tags, or an .lrc file with the
/// same name next to it. Lyrics with timings win (Troy wants them to follow the music): embedded timed lyrics,
/// then the .lrc file, then embedded plain text.
public enum LyricsReader {
    public static func lyrics(for track: Track) -> Lyrics? {
        let url = URL(fileURLWithPath: track.path)
        let embedded = embeddedLyrics(in: url)
        if case .timed = embedded { return embedded }
        if let fromFile = lrcFile(next: url) { return fromFile }
        return embedded
    }

    /// Plain lyrics spread evenly over the song, so they can still scroll along (roughly) with the music.
    /// A short lead-in and fade-out are left without lines.
    public static func estimatedTiming(_ text: String, duration: Double) -> [Lyrics.TimedLine] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let sung = lines.filter { !$0.isEmpty }
        guard !sung.isEmpty, duration > 0 else { return [] }
        let start = duration * 0.06, end = duration * 0.92
        let step = (end - start) / Double(sung.count)
        return sung.enumerated().map { .init(time: start + Double($0.offset) * step, text: $0.element) }
    }

    static func lrcFile(next url: URL) -> Lyrics? {
        let lrc = url.deletingPathExtension().appendingPathExtension("lrc")
        guard let data = try? Data(contentsOf: lrc),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let lines = LRCParser.parse(text)
        if !lines.isEmpty { return .timed(lines) }
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : .plain(plain)
    }

    /// Lyrics in the file's own tags. Some taggers store LRC text there; that shows in time too.
    static func embeddedLyrics(in url: URL) -> Lyrics? {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url),
              let text = file.metadata.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        let lines = LRCParser.parse(text)
        return lines.count >= 3 ? .timed(lines) : .plain(text)
    }
}

/// Reads LRC lyrics: "[01:23.45]Line", several times per line allowed ("[00:10.00][01:10.00]Chorus"),
/// "[offset:+250]" honoured, other tags ([ar:], [ti:]…) skipped. Pure logic, unit-tested.
public enum LRCParser {
    public static func parse(_ text: String) -> [Lyrics.TimedLine] {
        var lines: [Lyrics.TimedLine] = []
        var offset = 0.0
        let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("[offset:") {
                let value = line.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces)
                offset = (Double(value) ?? 0) / 1000
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            let matches = stamp.matches(in: line, range: range)
            guard let last = matches.last, let lastRange = Range(last.range, in: line) else { continue }
            let words = String(line[lastRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                func number(_ index: Int) -> Double? {
                    Range(match.range(at: index), in: line).flatMap { Double(line[$0]) }
                }
                guard let minutes = number(1), let seconds = number(2) else { continue }
                var fraction = 0.0
                if let part = Range(match.range(at: 3), in: line) {
                    let digits = String(line[part])
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                lines.append(.init(time: max(0, minutes * 60 + seconds + fraction - offset), text: words))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
