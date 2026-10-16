import Foundation

/// Rules for grouping tracks into artists and albums. Pure functions, unit-tested.
public enum LibraryKeys {
    public static let unknownArtist = "Unknown Artist"
    public static let variousArtists = "Various Artists"

    /// Lowercased, accent-insensitive, single-spaced. "Björk" and "bjork " match.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The artist an album is filed under.
    public static func albumArtist(albumArtist: String?, artist: String?, isCompilation: Bool) -> String {
        if let a = albumArtist?.nonEmpty { return a }
        if isCompilation { return variousArtists }
        return artist?.nonEmpty ?? unknownArtist
    }

    /// Album title, falling back to the containing folder's name for untagged files.
    public static func albumTitle(album: String?, fileURL: URL) -> String {
        album?.nonEmpty ?? fileURL.deletingLastPathComponent().lastPathComponent
    }

    public static func albumKey(albumArtist: String, albumTitle: String) -> String {
        normalize(albumArtist) + "|" + normalize(albumTitle)
    }

    /// First 4-digit run in a date tag: "2007-05-01" -> 2007, "c. 1999" -> 1999.
    public static func year(from releaseDate: String?) -> Int? {
        guard let text = releaseDate else { return nil }
        var digits = ""
        for ch in text {
            if ch.isASCII, ch.isNumber {
                digits.append(ch)
                if digits.count == 4, let y = Int(digits), (1000...2999).contains(y) { return y }
            } else {
                digits = ""
            }
        }
        return nil
    }

    /// Picks a cover image from a folder listing, by common file names.
    public static func bestCoverFile(in fileNames: [String]) -> String? {
        let preferred = ["cover", "folder", "front", "album", "albumart", "albumartlarge"]
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png"]
        let images = fileNames.filter {
            imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".")
        }
        for name in preferred {
            if let match = images.first(where: { ($0 as NSString).deletingPathExtension.lowercased() == name }) {
                return match
            }
        }
        return nil
    }
}

extension String {
    /// `nil` when empty or only whitespace.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
