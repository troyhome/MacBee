import AppKit
import AVFoundation
import Foundation

/// The poster saved inside a video file (the iTunes "covr" picture that VideoTagger and iTunes write into
/// MP4, M4V and MOV files), or else the poster set as the file's Finder icon (VideoTagger does that for every
/// file, MKV included). Read once per file and version (path + changed date), saved to the caches folder
/// and reused, so a page of cards doesn't read every file again.
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
        let path = video.path
        // The later of the file's modified date and its attributes' (a new Finder icon changes only the latter).
        let modified = await Task.detached(priority: .utility) { () -> TimeInterval? in
            let values = try? video.resourceValues(forKeys: [.contentModificationDateKey, .attributeModificationDateKey])
            let dates = [values?.contentModificationDate, values?.attributeModificationDate].compactMap { $0 }
            return dates.max()?.timeIntervalSince1970
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

    /// The embedded picture's bytes: the common "artwork" item first, then the iTunes cover, then the Finder icon.
    /// Only reads.
    public static func read(_ video: URL) async -> Data? {
        if readableExtensions.contains(video.pathExtension.lowercased()), let data = await readTags(video) { return data }
        return finderIconPoster(video)
    }

    /// The poster set as the file's own Finder icon, stretched back from the icon's square to a poster's 2:3 shape.
    /// Nil when the file has the normal icon.
    public static func finderIconPoster(_ video: URL) -> Data? {
        var info = [UInt8](repeating: 0, count: 32)
        guard getxattr(video.path, "com.apple.FinderInfo", &info, 32, 0, 0) == 32,
              (UInt16(info[8]) << 8 | UInt16(info[9])) & 0x0400 != 0 else { return nil } // "has custom icon"
        let icon = NSWorkspace.shared.icon(forFile: video.path)
        var square = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        guard let image = icon.cgImage(forProposedRect: &square, context: nil, hints: nil) else { return nil }
        let height = 1024, width = 683
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let poster = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: poster).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }

    static func readTags(_ video: URL) async -> Data? {
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
