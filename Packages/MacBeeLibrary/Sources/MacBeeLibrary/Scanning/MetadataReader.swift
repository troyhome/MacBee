import Foundation
import SFBAudioEngine

/// A file found while walking a folder.
struct FoundFile: Sendable {
    var path: String
    var stamp: FileStamp
    var createdAt: Date?
}

/// Reads tags, audio properties and cover art from one file.
struct MetadataReader: Sendable {
    let artwork: ArtworkStore
    let folderArt: FolderArtCache

    enum Outcome: Sendable {
        case success(ScannedTrack)
        case failure(path: String, reason: String)
    }

    func read(_ file: FoundFile) async -> Outcome {
        let url = URL(fileURLWithPath: file.path)
        let audioFile: AudioFile
        do {
            audioFile = try AudioFile(readingPropertiesAndMetadataFrom: url)
        } catch {
            return .failure(path: file.path, reason: error.localizedDescription)
        }

        var t = ScannedTrack(path: file.path, fileSize: file.stamp.size,
                             modifiedAt: file.stamp.modified, createdAt: file.createdAt)

        let m = audioFile.metadata
        t.title = m.title?.nonEmpty
        t.artist = m.artist?.nonEmpty
        t.albumArtist = m.albumArtist?.nonEmpty
        t.album = m.albumTitle?.nonEmpty
        t.genre = m.genre?.nonEmpty
        t.composer = m.composer?.nonEmpty
        t.year = LibraryKeys.year(from: m.releaseDate)
        t.trackNumber = m.trackNumber
        t.trackTotal = m.trackTotal
        t.discNumber = m.discNumber
        t.discTotal = m.discTotal
        t.isCompilation = m.isCompilation ?? false
        // For MP3s, check what the compilation frame actually says ("0" means no).
        if t.isCompilation, url.pathExtension.lowercased() == "mp3", let value = ID3Compilation.value(in: url) {
            t.isCompilation = value
        }
        t.rating = m.rating

        let p = audioFile.properties
        t.duration = p.duration ?? 0
        t.sampleRate = p.sampleRate
        t.bitDepth = p.bitDepth
        t.channels = p.channelCount.map { Int($0) }
        t.bitrate = p.bitrate
        t.codec = Self.codecName(pathExtension: url.pathExtension, formatName: p.formatName)

        // Embedded front cover first, then any embedded picture, then cover.jpg / folder.jpg. Empty pictures are
        // skipped: some taggers leave an empty one in front of the real cover.
        let pictures = m.attachedPictures.filter { !$0.imageData.isEmpty }
        let embedded = pictures.first { $0.type == .frontCover } ?? pictures.first
        if let data = embedded?.imageData {
            t.artwork = artwork.store(imageData: data)
        }
        if t.artwork == nil {
            t.artwork = await folderArt.artwork(forDirectory: url.deletingLastPathComponent())
        }
        return .success(t)
    }

    /// Short codec label for the UI.
    static func codecName(pathExtension: String, formatName: String?) -> String {
        switch pathExtension.lowercased() {
        case "flac": return "FLAC"
        case "wav", "wave": return "WAV"
        case "aif", "aiff", "aifc": return "AIFF"
        case "mp3": return "MP3"
        case "dsf", "dff": return "DSD"
        case "m4a", "mp4", "m4b", "alac":
            let name = formatName?.lowercased() ?? ""
            if name.contains("lossless") || name.contains("alac") { return "ALAC" }
            return "AAC"
        case "aac": return "AAC"
        case "ogg", "oga": return "Vorbis"
        case "opus": return "Opus"
        case "ape": return "APE"
        case "wv": return "WavPack"
        default: return pathExtension.uppercased()
        }
    }
}
