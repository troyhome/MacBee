import Foundation

/// Reading and writing M3U / M3U8 playlist files.
public enum M3UPlaylist {

    /// File paths listed in a playlist file, made absolute relative to the file's folder.
    /// Comment lines (#...) and web addresses are skipped; Windows-style backslashes are accepted.
    public static func parse(_ text: String, baseDirectory: URL) -> [String] {
        text.components(separatedBy: .newlines).compactMap { raw -> String? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if line.lowercased().hasPrefix("file://") {
                return URL(string: line)?.standardizedFileURL.path
            }
            if line.contains("://") { return nil }
            line = line.replacingOccurrences(of: "\\", with: "/")
            let url = line.hasPrefix("/") ? URL(fileURLWithPath: line)
                                           : baseDirectory.appendingPathComponent(line)
            return url.standardizedFileURL.path
        }
    }

    /// Reads a playlist file. M3U8 is UTF-8; older .m3u files may be Latin-1.
    public static func read(contentsOf url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return parse(text, baseDirectory: url.deletingLastPathComponent())
    }

    public enum PathStyle: String, CaseIterable, Sendable {
        /// Paths from where the playlist file is saved ("../Artist/Album/01.flac"), so the music and the
        /// playlist can move together or be opened from another computer. Songs on another drive keep full paths.
        case relative
        /// Full paths ("/Volumes/2 Set Music/Artist/Album/01.flac").
        case absolute
    }

    /// Text of an extended M3U8 file.
    public static func export(_ tracks: [Track], relativeTo directory: URL, style: PathStyle = .relative) -> String {
        var lines = ["#EXTM3U"]
        for track in tracks {
            lines.append("#EXTINF:\(Int(track.duration.rounded())),\(track.displayArtist) - \(track.displayTitle)")
            lines.append(style == .absolute ? track.path : relativePath(track.path, to: directory))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The path of a file as seen from `directory`, going up with ".." where needed. Files on another drive
    /// (no shared start below the drive) keep their full path.
    static func relativePath(_ path: String, to directory: URL) -> String {
        let from = directory.standardizedFileURL.pathComponents
        let to = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        var shared = 0
        while shared < min(from.count, to.count) && from[shared] == to[shared] { shared += 1 }
        // Only "/" (or "/Volumes/<drive>" not shared): different places, keep the full path.
        let volumeDepth = from.count > 1 && from[1] == "Volumes" ? 3 : 2
        guard shared >= volumeDepth else { return path }
        let ups = Array(repeating: "..", count: from.count - shared)
        return (ups + to[shared...]).joined(separator: "/")
    }
}
