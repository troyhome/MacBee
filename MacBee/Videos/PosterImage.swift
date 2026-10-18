import AppKit
import ImageIO
import MacBeeVideo
import SwiftUI

/// A poster from a file next to the video (or from Plex), shrunk and cached. Without one, a still from the
/// video itself (`previewFile`): blurred to fill the poster, with the whole frame in the middle. Without that,
/// a plain card with the title, tinted by the title so cards look different from each other.
struct PosterImage: View {
    let path: String?
    let title: String
    var maxPixels = 600
    var previewFile: VideoFile?

    @Environment(\.theme) private var theme
    @State private var image: NSImage?
    @State private var frame: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let frame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 18)
                    .overlay(Color.black.opacity(0.25))
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.5), radius: 8)
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
        .clipped()
        .task(id: path) {
            image = await PosterCache.shared.image(at: path, maxPixels: maxPixels)
            if image == nil, let previewFile, let still = await VideoFrames.shared.frame(for: previewFile) {
                frame = await PosterCache.shared.image(at: still, maxPixels: maxPixels)
            }
        }
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

/// Stills taken from videos without posters, two at a time so a page of cards doesn't flood the drive.
actor VideoFrames {
    static let shared = VideoFrames()
    private var known: [String: String?] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func frame(for file: VideoFile) async -> String? {
        if let found = known[file.path] { return found }
        while running >= 2 { await withCheckedContinuation { waiting.append($0) } }
        if let found = known[file.path] { return found }
        running += 1
        let path = await Task.detached(priority: .utility) {
            VideoThumbnailer.thumbnail(for: file.url, size: file.size)?.path
        }.value
        running -= 1
        if !waiting.isEmpty { waiting.removeFirst().resume() }
        known[file.path] = path
        return path
    }
}
