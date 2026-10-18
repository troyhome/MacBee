import AVFoundation
import AppKit
import Observation

/// Finds music videos (MP4, M4V, MOV) in the music folders and makes thumbnails for them.
/// Videos aren't stored in the music database; the folders are searched again when the Videos page opens.
@MainActor
@Observable
final class VideoLibrary {
    private(set) var videos: [VideoItem] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    /// Paths of liked videos (shown in Collection > Videos). Saved on this Mac.
    private(set) var likedPaths: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "likedVideos") ?? [])

    @ObservationIgnored private var thumbnails: [URL: NSImage] = [:]

    /// Searches these folders (skipping any that can't be reached) and replaces the list.
    func refresh(folders: [URL]) async {
        guard !isSearching else { return }
        isSearching = true
        let found = await Task.detached(priority: .utility) { Self.findVideos(in: folders) }.value
        videos = found
        isSearching = false
        hasSearched = true
    }

    func isLiked(_ video: VideoItem) -> Bool {
        likedPaths.contains(video.url.path)
    }

    func toggleLike(_ video: VideoItem) {
        if likedPaths.remove(video.url.path) == nil { likedPaths.insert(video.url.path) }
        UserDefaults.standard.set(Array(likedPaths).sorted(), forKey: "likedVideos")
    }

    /// Videos whose title or folder contains the text, optionally only liked ones.
    func videos(matching text: String, likedOnly: Bool) -> [VideoItem] {
        let query = text.trimmingCharacters(in: .whitespaces)
        return videos.filter { video in
            (!likedOnly || isLiked(video))
                && (query.isEmpty || video.title.localizedCaseInsensitiveContains(query)
                    || video.folderName.localizedCaseInsensitiveContains(query))
        }
    }

    /// A frame from about 10 seconds in (or the start of short videos), cached for this session.
    func thumbnail(for video: VideoItem) async -> NSImage? {
        if let cached = thumbnails[video.url] { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        for seconds in [10.0, 0.0] {
            if let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image {
                let image = NSImage(cgImage: frame, size: .zero)
                thumbnails[video.url] = image
                return image
            }
        }
        return nil
    }

    nonisolated private static func findVideos(in folders: [URL]) -> [VideoItem] {
        var result: [VideoItem] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        for folder in folders {
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in walker where VideoItem.extensions.contains(url.pathExtension.lowercased()) {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                result.append(VideoItem(url: url,
                                        title: url.deletingPathExtension().lastPathComponent,
                                        folderName: url.deletingLastPathComponent().lastPathComponent,
                                        modified: values?.contentModificationDate ?? .distantPast))
            }
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
