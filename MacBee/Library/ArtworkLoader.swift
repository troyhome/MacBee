import Foundation
import ImageIO
import MacBeeLibrary

/// Loads cached covers as small thumbnails, off the main thread, and keeps recent ones in memory.
@MainActor
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    private let cache = NSCache<NSString, CGImage>()

    private init() {
        // Limit by memory, not count: 800 large covers alone could take over 500 MB.
        cache.totalCostLimit = 150 * 1024 * 1024
    }

    func image(for artworkId: Int64?, in library: MusicLibrary, pixelSize: Int) async -> CGImage? {
        guard let artworkId else { return nil }
        let key = "\(artworkId)@\(pixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = await library.artworkURL(for: artworkId) else { return nil }
        let image = await Task.detached(priority: .utility) {
            Self.thumbnail(of: url, maxPixelSize: pixelSize)
        }.value
        if let image { cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height) }
        return image
    }

    nonisolated private static func thumbnail(of url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
