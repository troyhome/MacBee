import Foundation
import SFBAudioEngine

/// Embeds a cover picture into song files directly, with SFBAudioEngine.
///
/// This replaced running TagBee's command-line helper, which the App Store sandbox doesn't allow.
public enum CoverWriter {
    public struct Failure: Error, Sendable {
        public let path: String
        public let reason: String
    }

    /// Replaces each file's front cover with `image` (JPEG or PNG). Other pictures (back cover, artist, ...) stay.
    /// Returns the files that couldn't be written; the others are saved.
    public static func embed(_ image: Data, inFilesAt paths: [String]) -> [Failure] {
        var failures: [Failure] = []
        for path in paths {
            do {
                let file = try AudioFile(readingPropertiesAndMetadataFrom: URL(fileURLWithPath: path))
                file.metadata.removeAttachedPicturesOfType(.frontCover)
                // A cover with no type counts as the front cover in many players; replace it too.
                file.metadata.removeAttachedPicturesOfType(.other)
                file.metadata.attachPicture(AttachedPicture(imageData: image, type: .frontCover))
                try file.writeMetadata()
            } catch {
                failures.append(Failure(path: path, reason: error.localizedDescription))
            }
        }
        return failures
    }
}
