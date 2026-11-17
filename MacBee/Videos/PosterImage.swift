import AppKit
import ImageIO
import MacBeeVideo
import SwiftUI

/// A poster from a file next to the video (or from Plex), shrunk and cached. Without one, the poster saved
/// inside the video file (MP4/M4V/MOV). Without that, a still from the
/// video itself (`previewFile`): blurred to fill the poster, with the whole frame in the middle. Without that,
/// a plain card with the title, tinted by the title so cards look different from each other.
struct PosterImage: View {
    let path: String?
    let title: String
    var maxPixels = 600
    var previewFile: VideoFile?
    /// Posters put the title on a video still; wide thumbnails (Continue Watching) show the still alone.
    var titlesStill = true

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
                // No poster: a still from the video, cropped like a poster, with the title on it so it reads
                // as a cover rather than a blurry picture.
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                if titlesStill {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .padding(12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
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
        .task(id: "\(path ?? "")#\(PosterCache.shared.generation)") {
            var found = await PosterCache.shared.image(at: path, maxPixels: maxPixels)
            // The poster saved inside the video (MP4/M4V/MOV) comes before a still from the video.
            // Wide thumbnails (titlesStill false) keep showing a still.
            if found == nil, titlesStill, let previewFile,
               let embedded = await EmbeddedArtwork.shared.poster(for: previewFile.url) {
                found = await PosterCache.shared.image(at: embedded, maxPixels: maxPixels)
            }
            image = found
            if found != nil {
                frame = nil
            } else if let previewFile, let still = await VideoFrames.shared.frame(for: previewFile) {
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

/// Keeps shrunken posters in memory (up to about 80 MB). A picture replaced on disk (same name, newer date) is
/// read again; after each video scan the posters on screen check their files once more.
@MainActor
@Observable
final class PosterCache {
    static let shared = PosterCache()
    /// Goes up after each video scan, so posters on screen look at their files again.
    private(set) var generation = 0

    func filesMayHaveChanged() { generation += 1 }

    /// Pictures the person asked to read again (right-click > Refresh Poster), with how many times.
    @ObservationIgnored private var reloads: [String: Int] = [:]

    /// Forgets the shrunken copy of this picture so it's read from disk again.
    func reload(_ path: String?) {
        if let path { reloads[path, default: 0] += 1 }
        generation += 1
    }

    @ObservationIgnored
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 80_000_000
        return cache
    }()

    func image(at path: String?, maxPixels: Int) async -> NSImage? {
        guard let path else { return nil }
        // The file's date is part of the key, so a new poster.jpg saved over the old one shows up.
        let modified = await Task.detached(priority: .utility) {
            (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }.value
        let key = "\(path)#\(maxPixels)#\(modified)#\(reloads[path] ?? 0)" as NSString
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
