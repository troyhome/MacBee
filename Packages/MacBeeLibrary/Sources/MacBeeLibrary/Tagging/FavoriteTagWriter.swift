import Foundation
import SFBAudioEngine

/// Saves the heart in the song file itself, as a FAVORITE=1 (or 0) tag, so it travels with the file to other Macs
/// and survives a rebuilt library. Only formats with free-form tags can carry it: FLAC, Ogg (Vorbis, Opus, FLAC).
/// MP3, AAC, ALAC, WAV, AIFF and DSD keep their hearts in MacBee's library only.
public enum FavoriteTagWriter {
    public static let tagName = "FAVORITE"
    static let supportedExtensions: Set<String> = ["flac", "ogg", "oga", "opus"]

    public static func canStore(path: String) -> Bool {
        supportedExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Writes the tag into each file that can carry it. Returns the paths that couldn't be written.
    @discardableResult
    public static func write(_ isFavorite: Bool, toFilesAt paths: [String]) -> [String] {
        var failed: [String] = []
        for path in paths where canStore(path: path) {
            do {
                let file = try AudioFile(readingPropertiesAndMetadataFrom: URL(fileURLWithPath: path))
                var extra = file.metadata.additionalMetadata ?? [:]
                // Already says so: leave the file (and its modified date) alone.
                if (extra[tagName] as? String) == (isFavorite ? "1" : "0") { continue }
                extra[tagName] = isFavorite ? "1" : "0"
                file.metadata.additionalMetadata = extra
                try file.writeMetadata()
            } catch {
                failed.append(path)
            }
        }
        return failed
    }

    /// The heart a file carries: true, false, or nil when it has no FAVORITE tag.
    static func value(in metadata: AudioMetadata) -> Bool? {
        guard let extra = metadata.additionalMetadata,
              let raw = extra.first(where: { ($0.key as? String)?.uppercased() == tagName })?.value as? String
        else { return nil }
        switch raw.trimmingCharacters(in: .whitespaces) {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }
}
