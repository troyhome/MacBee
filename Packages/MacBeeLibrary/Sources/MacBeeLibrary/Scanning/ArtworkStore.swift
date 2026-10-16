import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves cover images to a local cache folder, one file per unique image.
///
/// Images are resized to at most 1200 px (sharp on a full-screen Now Playing view)
/// and stored as JPEG, named by a hash of the original, so an album's 12 identical
/// embedded covers are stored once. Local copies also mean covers show instantly
/// even when the network drive is slow or offline.
public struct ArtworkStore: Sendable {
    public let directory: URL
    public let maxPixelSize: Int

    public init(directory: URL, maxPixelSize: Int = 1200) {
        self.directory = directory
        self.maxPixelSize = maxPixelSize
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func url(for ref: ArtworkRef) -> URL {
        directory.appendingPathComponent("\(ref.hash).\(ref.fileExtension)")
    }

    /// Caches the image (if new) and returns its reference, or nil if it isn't a readable image.
    func store(imageData: Data) -> ArtworkRef? {
        guard !imageData.isEmpty else { return nil }
        let hash = SHA256.hash(data: imageData).prefix(16).map { String(format: "%02x", $0) }.joined()
        let ref = ArtworkRef(hash: hash, fileExtension: "jpg")
        let destination = url(for: ref)
        if FileManager.default.fileExists(atPath: destination.path) { return ref }

        guard let resized = Self.resizedJPEG(from: imageData, maxPixelSize: maxPixelSize) else { return nil }
        do {
            try resized.write(to: destination, options: .atomic)
            return ref
        } catch {
            return nil
        }
    }

    static func resizedJPEG(from data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Finds cover.jpg / folder.jpg style images once per folder during a scan.
actor FolderArtCache {
    private let store: ArtworkStore
    private var results: [String: Task<ArtworkRef?, Never>] = [:]

    init(store: ArtworkStore) {
        self.store = store
    }

    func artwork(forDirectory directory: URL) async -> ArtworkRef? {
        let key = directory.path
        if let existing = results[key] { return await existing.value }
        let store = self.store
        let task = Task.detached(priority: .utility) { () -> ArtworkRef? in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: key)) ?? []
            guard let file = LibraryKeys.bestCoverFile(in: names),
                  let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
            return store.store(imageData: data)
        }
        results[key] = task
        return await task.value
    }
}
