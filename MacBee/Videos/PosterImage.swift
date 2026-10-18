import AppKit
import ImageIO
import SwiftUI

/// A poster from a file next to the video, shrunk and cached. Without one, a plain card with the title,
/// tinted by the title so cards look different from each other.
struct PosterImage: View {
    let path: String?
    let title: String
    var maxPixels = 600

    @Environment(\.theme) private var theme
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .padding(12)
            }
        }
        .task(id: path) { image = await PosterCache.shared.image(at: path, maxPixels: maxPixels) }
    }

    private var tint: Color {
        let hues: [Double] = [0.58, 0.04, 0.33, 0.75, 0.12, 0.92, 0.48]
        let index = abs(title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % hues.count
        return Color(hue: hues[index], saturation: 0.55, brightness: 0.45)
    }
}

/// Keeps shrunken posters in memory (up to about 80 MB).
@MainActor
final class PosterCache {
    static let shared = PosterCache()
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 80_000_000
        return cache
    }()

    func image(at path: String?, maxPixels: Int) async -> NSImage? {
        guard let path else { return nil }
        let key = "\(path)#\(maxPixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let loaded = await Task.detached(priority: .utility) { () -> (NSImage, Int)? in
            let url = URL(fileURLWithPath: path) as CFURL
            guard let source = CGImageSourceCreateWithURL(url, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return nil }
            return (NSImage(cgImage: cgImage, size: .zero), cgImage.width * cgImage.height * 4)
        }.value
        guard let (image, cost) = loaded else { return nil }
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
