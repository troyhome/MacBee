import CoreGraphics
import Foundation
import ImageIO
import Libmpv
import UniformTypeIdentifiers

/// Makes a still picture from a video (any format mpv plays, MKV included), about a tenth of the way in.
/// mpv decodes one frame without a window or sound and hands back its pixels; pictures are saved once and reused.
public enum VideoThumbnailer {
    public static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee/VideoFrames", isDirectory: true)
    }

    /// The saved picture for this video, making it first if needed. Slow (reads part of the file), so call it
    /// off the main thread. Nil when the video can't be read.
    public static func thumbnail(for video: URL, size: Int64) -> URL? {
        let destination = cacheDirectory.appendingPathComponent("\(stableName(video.path))-\(size).jpg")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        guard let image = frame(of: video) else { return nil }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(output) ? destination : nil
    }

    /// One decoded frame, scaled to 640 wide.
    static func frame(of video: URL) -> CGImage? {
        guard let mpv = mpv_create() else { return nil }
        defer { mpv_terminate_destroy(mpv) }
        for (option, value) in [("vo", "null"), ("ao", "null"), ("aid", "no"), ("sid", "no"), ("start", "10%"),
                                ("pause", "yes"), ("hwdec", "no"), ("vf", "scale=640:-2"), ("terminal", "no"),
                                ("idle", "yes"), ("load-scripts", "no")] {
            mpv_set_option_string(mpv, option, value)
        }
        guard mpv_initialize(mpv) >= 0 else { return nil }
        command(mpv, ["loadfile", video.path])
        // Wait (up to 20 s; network drives can be slow) until the first frame at the start point is ready.
        let deadline = Date().addingTimeInterval(20)
        var ready = false
        waiting: while Date() < deadline {
            guard let event = mpv_wait_event(mpv, 1) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_PLAYBACK_RESTART: ready = true; break waiting
            case MPV_EVENT_END_FILE, MPV_EVENT_SHUTDOWN: break waiting
            default: continue
            }
        }
        guard ready else { return nil }
        return screenshot(mpv)
    }

    /// `screenshot-raw` gives the frame as BGR0 pixels: w, h, stride and data in a node map.
    private static func screenshot(_ mpv: OpaquePointer) -> CGImage? {
        let words: [String] = ["screenshot-raw", "video"]
        var args: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) } + [nil]
        defer { args.forEach { free($0) } }
        var result = mpv_node()
        let status = args.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                mpv_command_ret(mpv, $0, &result)
            }
        }
        guard status >= 0 else { return nil }
        defer { mpv_free_node_contents(&result) }
        guard result.format == MPV_FORMAT_NODE_MAP, let list = result.u.list?.pointee else { return nil }
        var width = 0, height = 0, stride = 0
        var pixels: UnsafeMutableRawPointer?
        var byteCount = 0
        for index in 0..<Int(list.num) {
            let key = String(cString: list.keys[index]!)
            let value = list.values[index]
            switch key {
            case "w": width = Int(value.u.int64)
            case "h": height = Int(value.u.int64)
            case "stride": stride = Int(value.u.int64)
            case "data":
                if value.format == MPV_FORMAT_BYTE_ARRAY, let array = value.u.ba?.pointee {
                    pixels = array.data
                    byteCount = array.size
                }
            default: break
            }
        }
        guard width > 0, height > 0, stride > 0, let pixels, byteCount >= stride * height else { return nil }
        let data = Data(bytes: pixels, count: stride * height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func command(_ mpv: OpaquePointer, _ words: [String]) {
        var args: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) } + [nil]
        defer { args.forEach { free($0) } }
        args.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                _ = mpv_command(mpv, $0)
            }
        }
    }

    /// A file name that stays the same between launches (Swift's hashValue changes every launch).
    private static func stableName(_ path: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in path.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}
