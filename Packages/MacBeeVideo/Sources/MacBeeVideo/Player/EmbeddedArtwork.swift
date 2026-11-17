import AVFoundation
import Foundation

/// The poster saved inside a video file (the iTunes "covr" picture that VideoTagger and iTunes write into
/// MP4, M4V and MOV files). Read once per file and version (path + modified date), saved to the caches folder
/// and reused, so a page of cards doesn't read every file again. MKV is not read (no cover there).
public actor EmbeddedArtwork {
    public static let shared = EmbeddedArtwork()

    public static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee/EmbeddedPosters", isDirectory: true)
    }

    static let readableExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// Known answers for this launch, keyed by path + modified date: the saved picture's path, or nil for none.
    private var known: [String: String?] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// The path of a picture file holding this video's embedded poster, or nil when it has none.
    public func poster(for video: URL) async -> String? {
        guard Self.readableExtensions.contains(video.pathExtension.lowercased()) else { return nil }
        let path = video.path
        let modified = await Task.detached(priority: .utility) {
            (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?.timeIntervalSince1970
        }.value
        guard let modified else { return nil }
        let key = "\(path)#\(Int(modified))"
        if let found = known[key] { return found }
        // Two at a time, like the video stills, so network drives aren't flooded.
        while running >= 2 { await withCheckedContinuation { waiting.append($0) } }
        if let found = known[key] { return found }
        running += 1
        let saved = await Self.cachedOrRead(video, modified: Int(modified))
        running -= 1
        if !waiting.isEmpty { waiting.removeFirst().resume() }
        known[key] = saved
        return saved
    }

    /// Forgets what was found for this video (right-click > Refresh Poster), so the file is read again.
    public func forget(_ video: URL) {
        let path = video.path
        known = known.filter { !$0.key.hasPrefix(path + "#") }
        let prefix = VideoThumbnailer.stableName(path) + "-"
        let folder = Self.cacheDirectory
        if let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for name in names where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    /// Looks in the caches folder first ("none" files remember videos without a poster), then reads the video.
    private static func cachedOrRead(_ video: URL, modified: Int) async -> String? {
        let base = "\(VideoThumbnailer.stableName(video.path))-\(modified)"
        let folder = cacheDirectory
        for ext in ["jpg", "png"] {
            let file = folder.appendingPathComponent("\(base).\(ext)")
            if FileManager.default.fileExists(atPath: file.path) { return file.path }
        }
        let none = folder.appendingPathComponent("\(base).none")
        if FileManager.default.fileExists(atPath: none.path) { return nil }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Older versions of this video's poster are no longer needed.
        let prefix = VideoThumbnailer.stableName(video.path) + "-"
        if let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for name in names where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        guard let data = await read(video) else {
            FileManager.default.createFile(atPath: none.path, contents: Data())
            return nil
        }
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let file = folder.appendingPathComponent("\(base).\(isPNG ? "png" : "jpg")")
        do { try data.write(to: file, options: .atomic) } catch { return nil }
        return file.path
    }

    /// The embedded picture's bytes: the common "artwork" item first, then the iTunes cover. Only reads.
    public static func read(_ video: URL) async -> Data? {
        let asset = AVURLAsset(url: video)
        if let common = try? await asset.load(.commonMetadata),
           let data = await firstData(AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork)) {
            return data
        }
        if let itunes = try? await asset.loadMetadata(for: .iTunesMetadata),
           let data = await firstData(AVMetadataItem.metadataItems(from: itunes, filteredByIdentifier: .iTunesMetadataCoverArt)) {
            return data
        }
        return nil
    }

    private static func firstData(_ items: [AVMetadataItem]) async -> Data? {
        for item in items {
            if let data = try? await item.load(.dataValue), !data.isEmpty { return data }
        }
        return nil
    }
}
