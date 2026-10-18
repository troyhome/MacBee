import Foundation

/// Reads titles, years, episode numbers and quality from messy file and folder names, e.g.
/// "Drive (2011) V2 (2160p BluRay x265 10bit HDR Tigole).mkv", "Scrubs.(2026).-.S01E05.-.My.Angel.mkv",
/// "The.Bridge.on.the.River.Kwai.1957.1080p.BluRay.x264.YIFY.mp4". Pure functions, unit-tested.
public enum VideoNameParser {
    public struct Name: Equatable, Sendable {
        public var title: String
        public var year: Int?
    }

    public struct EpisodeMarker: Equatable, Sendable {
        public var season: Int
        public var episode: Int
        /// Text after the marker, cleaned (often the episode title).
        public var rest: String?
    }

    /// File types MacBee plays through mpv.
    public static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts", "wmv", "mpg", "mpeg"]

    /// Title and year from a file or folder name (extension, if any, should be removed first).
    public static func name(from raw: String) -> Name {
        var text = spaced(raw)
        // Collection numbering in front: "007 - Dr. No", "01 Die Hard".
        text = text.replacingOccurrences(of: #"^\s*(\d{2,3}\s*-\s+|0\d\s+)"#, with: "", options: .regularExpression)
        // Drop [tags] and {tags} anywhere.
        text = text.replacingOccurrences(of: #"\[[^\]]*\]|\{[^}]*\}"#, with: " ", options: .regularExpression)
        // A year in (parentheses) or standing alone. The title is everything before it.
        var year: Int?
        if let match = text.range(of: #"\(?\b(19[2-9]\d|20[0-4]\d)\b\)?"#, options: .regularExpression) {
            let candidate = text[match].filter(\.isNumber)
            let before = String(text[..<match.lowerBound])
            // "(1982) Blade Runner": year first, title after.
            if before.trimmingCharacters(in: .whitespaces).isEmpty {
                year = Int(candidate)
                text = String(text[match.upperBound...])
                text = cutAtTags(text)
            } else {
                year = Int(candidate)
                text = before
            }
        } else {
            text = cutAtTags(text)
        }
        return Name(title: tidy(text), year: year)
    }

    /// Season and episode from names like "S01E05", "s01e01", "1x02", "2x01". Nil for movies.
    public static func episode(in raw: String) -> EpisodeMarker? {
        let text = spaced(raw)
        let patterns = [#"\b[Ss](\d{1,2})\s?[Ee](\d{1,3})(?:-?[Ee]\d{1,3})*\b"#, #"\b(\d{1,2})[xX](\d{2,3})\b"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let seasonRange = Range(match.range(at: 1), in: text),
                  let episodeRange = Range(match.range(at: 2), in: text),
                  let whole = Range(match.range, in: text),
                  let season = Int(text[seasonRange]), let episode = Int(text[episodeRange]) else { continue }
            var rest = String(text[whole.upperBound...])
            rest = rest.replacingOccurrences(of: #"\[[^\]]*\]|\{[^}]*\}"#, with: " ", options: .regularExpression)
            rest = cutAtTags(rest)
            rest = tidy(rest)
            return EpisodeMarker(season: season, episode: episode, rest: rest.isEmpty ? nil : rest)
        }
        return nil
    }

    /// Season number from a folder name like "Season 02", "S01", "Community S3". Nil if there isn't one.
    public static func seasonNumber(inFolder raw: String) -> Int? {
        let text = spaced(raw)
        for pattern in [#"(?i)\bseason\s*(\d{1,2})\b"#, #"(?i)\bS(\d{1,2})\b"#] {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return Int(text[range].filter(\.isNumber))
            }
        }
        return nil
    }

    public static func is4K(_ raw: String) -> Bool {
        raw.range(of: #"(?i)(2160p|\b4k\b|\buhd\b)"#, options: .regularExpression) != nil
    }

    public static func isHDR(_ raw: String) -> Bool {
        raw.range(of: #"(?i)(\bhdr(10)?\+?\b|\bdv\b|dolby\.?\s?vision|\bdovi\b)"#, options: .regularExpression) != nil
    }

    /// Sample clips that come with downloads.
    public static func isSample(_ raw: String) -> Bool {
        raw.range(of: #"(?i)\bsample\b"#, options: .regularExpression) != nil
    }

    // MARK: - Helpers

    /// Dots and underscores become spaces when the name has no spaces of its own ("The.Big.Short").
    static func spaced(_ raw: String) -> String {
        var text = raw
        if !text.contains(" ") || text.filter({ $0 == "." }).count >= 3 {
            text = text.replacingOccurrences(of: ".", with: " ")
        }
        return text.replacingOccurrences(of: "_", with: " ")
    }

    /// Cuts the name where release tags start ("1080p", "BluRay", "x265", "WEBRip", …).
    static func cutAtTags(_ text: String) -> String {
        let tags = #"(?i)\b(2160p|1080p|720p|480p|4k|uhd|bluray|blu-ray|brrip|bdrip|web-?dl|webrip|web|hdtv|dvdrip|x264|x265|h ?264|h ?265|hevc|10bit|hdr|remux|complete|retail|amzn|nf|pcok|ddp?5 1|aac|yify|rarbg|proper|repack|extended|unrated)\b"#
        guard let range = text.range(of: tags, options: .regularExpression) else { return text }
        return String(text[..<range.lowerBound])
    }

    /// Single spaces, no stray dashes or brackets at the ends.
    static func tidy(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"[()]"#, with: " ", options: .regularExpression)
        result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let junk = CharacterSet(charactersIn: " -–—.,:;")
        result = result.trimmingCharacters(in: junk)
        return result
    }
}
