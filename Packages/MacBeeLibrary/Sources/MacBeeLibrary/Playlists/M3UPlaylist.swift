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

    /// Text of an extended M3U8 file. Songs inside `directory` (where the file is saved) get relative paths,
    /// so the folder can be moved or opened from another computer; everything else gets full paths.
    public static func export(_ tracks: [Track], relativeTo directory: URL) -> String {
        var lines = ["#EXTM3U"]
        for track in tracks {
            lines.append("#EXTINF:\(Int(track.duration.rounded())),\(track.displayArtist) - \(track.displayTitle)")
            lines.append(relativePath(track.path, to: directory))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func relativePath(_ path: String, to directory: URL) -> String {
        let folder = directory.standardizedFileURL.path
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
