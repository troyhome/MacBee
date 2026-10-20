import Foundation
import SFBAudioEngine

/// Copy To: puts playlists (or the whole library) on a music player, SD card or drive. Songs go to
/// Artist/Album/## - Title.ext and each playlist gets an .m3u8 in a Playlists folder.
///
/// It works in three steps (Troy): `scan` looks at the device and sorts every song into new, changed,
/// moved (a song MacBee copied before whose name changed after a tag edit), found under another name (the same
/// song put there some other way), unchanged, and no longer needed. `job` turns that report and the chosen
/// options into a list of file operations, which the app runs one at a time (so it can pause, stop, and
/// resume later, even after the device was unplugged) with `perform`. Files MacBee didn't put there are only
/// touched when the person chooses to replace songs found under another name.
public enum DeviceSync {
    /// One playlist (or smart playlist / saved mix) to put on the device. An empty name (the entire library)
    /// copies the songs without writing a playlist file.
    public struct Source: Sendable {
        public var name: String
        public var tracks: [Track]
        public init(name: String, tracks: [Track]) {
            self.name = name
            self.tracks = tracks
        }
    }

    /// A file on the device: its size and when it was last changed.
    public struct FileInfo: Codable, Sendable, Equatable {
        public var size: Int64
        public var modified: Date
        public init(size: Int64, modified: Date) {
            self.size = size
            self.modified = modified
        }
    }

    /// A song to copy: from the library to `destination` (relative to the device), possibly in place of
    /// another file already on the device (`replacing`).
    public struct Item: Codable, Sendable, Hashable {
        public var source: String
        public var destination: String
        public var size: Int64
        public var replacing: String?
    }

    /// What's on the device compared with what should be there.
    public struct Scan: Sendable {
        /// Not on the device yet.
        public var newSongs: [Item] = []
        /// On the device under the right name, but the library's file is newer or a different size (tags or
        /// cover edited since): replaced.
        public var changed: [Item] = []
        /// Copied by MacBee before under a name that's now out of date (title, album, artist or number edited):
        /// copied under the new name and the old copy removed.
        public var moved: [Item] = []
        /// The same song already on the device under a different name, not put there by MacBee.
        public var foundElsewhere: [Item] = []
        public var unchanged = 0
        /// Songs MacBee copied before that no chosen playlist needs any more.
        public var unneeded: [String] = []
        /// Files on the device MacBee didn't put there and that match no song being copied (left alone).
        public var otherFiles = 0
        /// Playlist files to write: relative path -> the songs' device paths.
        public var playlists: [String: [PlaylistLine]] = [:]
        /// What MacBee put on the device before this sync.
        public var previousManifest: [String] = []

        public var bytesToCopy: Int64 { (newSongs + changed + moved + foundElsewhere).reduce(0) { $0 + $1.size } }
    }

    public struct PlaylistLine: Codable, Sendable, Hashable {
        public var path: String
        public var info: String
    }

    /// How to go ahead after the scan.
    public struct Choices: Codable, Sendable, Equatable {
        public enum Elsewhere: String, Codable, Sendable, CaseIterable {
            /// Copy MacBee's file and delete the other one.
            case replace
            /// Copy MacBee's file and keep the other one too.
            case keepBoth
            /// Leave the other file; playlists point at it.
            case skip
        }

        public var copyNew = true
        public var replaceChanged = true
        public var elsewhere = Elsewhere.skip
        public var removeUnneeded = true
        public init() {}
    }

    /// One step of a copy.
    public enum Operation: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable { case new, replace, move, elsewhereReplace, elsewhereKeepBoth }
        case copy(Item, Kind)
        case remove(String)
    }

    /// A copy in progress, saved so it can be paused and picked up later.
    public struct Job: Codable, Sendable {
        public var device: String
        public var operations: [Operation]
        /// How many operations are done.
        public var next = 0
        public var playlists: [String: String]
        /// What MacBee has put on the device so far (updated as files are copied and removed).
        public var manifest: [String]
        public var report = Report()
    }

    /// What a copy did.
    public struct Report: Codable, Sendable, Equatable {
        public var copiedNew = 0
        public var replaced = 0
        public var moved = 0
        public var replacedElsewhere = 0
        public var keptBoth = 0
        public var removed = 0
        public var bytes: Int64 = 0
        public var failed: [Failure] = []
        public var started = Date()
        public var finished: Date?
        public var stoppedEarly = false

        public struct Failure: Codable, Sendable, Equatable {
            public var path: String
            public var reason: String
            public init(path: String, reason: String) {
                self.path = path
                self.reason = reason
            }
        }
    }

    /// MacBee's record of what it put on the device.
    public static let manifestName = ".macbee-sync.json"
    public static let playlistFolder = "Playlists"
    static let audioExtensions: Set<String> = ["flac", "mp3", "m4a", "aac", "alac", "wav", "aif", "aiff", "ogg", "opus",
                                               "wv", "ape", "dsf", "dff", "mpc", "wma"]

    /// Where a song goes on the device: "Artist/Album/03 - Title.flac" (disc number first for multi-disc albums).
    public static func devicePath(for track: Track) -> String {
        let artist = safe(track.displayAlbumArtist.isEmpty ? (track.artist ?? "Unknown Artist") : track.displayAlbumArtist)
        let album = safe(track.displayAlbum.isEmpty ? "Unknown Album" : track.displayAlbum)
        var number = track.trackNumber.map { String(format: "%02d", $0) } ?? "00"
        if let disc = track.discNumber, (track.discTotal ?? 1) > 1 { number = "\(disc)-\(number)" }
        let ext = (track.path as NSString).pathExtension.lowercased()
        return "\(artist)/\(album)/\(number) - \(safe(track.displayTitle)).\(ext)"
    }

    /// The same song regardless of file name: artist, title and album, folded like the duplicate finder does.
    public static func songKey(artist: String?, title: String?, album: String?) -> String {
        [artist ?? "", title ?? "", album ?? ""].map(DuplicateFinder.fingerprint).joined(separator: "|")
    }

    /// Sorts every song into what needs doing.
    /// - `existing`: what's on the device now (relative path -> size and date).
    /// - `sourceDate`: when a library file was last changed.
    /// - `identify`: for a device file that isn't where any song should go, its song key and length (read from
    ///   its tags), or nil if it isn't a song. Only called for audio files.
    public static func scan(sources: [Source], existing: [String: FileInfo], previousManifest: [String],
                            sourceDate: (String) -> Date?,
                            identify: (String) -> (key: String, seconds: Double)?) -> Scan {
        var scan = Scan()
        scan.previousManifest = previousManifest
        let manifest = Set(previousManifest)
        var wanted: [String: Track] = [:]
        for source in sources {
            var lines: [PlaylistLine] = []
            for track in source.tracks {
                let path = devicePath(for: track)
                wanted[path] = wanted[path] ?? track
                lines.append(.init(path: path, info: "\(Int(track.duration.rounded())),\(track.displayArtist) - \(track.displayTitle)"))
            }
            if !source.name.isEmpty { scan.playlists["\(playlistFolder)/\(safe(source.name)).m3u8"] = lines }
        }

        var missing: [(path: String, track: Track)] = []
        for (path, track) in wanted.sorted(by: { $0.key < $1.key }) {
            let item = Item(source: track.path, destination: path, size: track.fileSize)
            guard let there = existing[path] else { missing.append((path, track)); continue }
            // Copies keep the library file's date, so a newer library file means it was edited since.
            let newer = sourceDate(track.path).map { $0.timeIntervalSince(there.modified) > 2 } ?? false
            if there.size != track.fileSize || newer { scan.changed.append(item) } else { scan.unchanged += 1 }
        }

        // Device files that aren't where any song should go: maybe a song under an old or different name.
        var waiting: [String: [(path: String, track: Track)]] = [:]
        for entry in missing {
            let key = songKey(artist: entry.track.artist ?? entry.track.displayArtist, title: entry.track.displayTitle,
                              album: entry.track.album ?? entry.track.displayAlbum)
            waiting[key, default: []].append(entry)
        }
        var matched = Set<String>() // wanted paths already paired with a device file
        let others = existing.keys.filter { path in
            wanted[path] == nil && path != manifestName && !path.hasPrefix(playlistFolder + "/")
        }.sorted()
        for path in others {
            let isAudio = audioExtensions.contains((path as NSString).pathExtension.lowercased())
            if isAudio, let found = identify(path),
               let entry = waiting[found.key]?.first(where: { !matched.contains($0.path) && abs($0.track.duration - found.seconds) <= 2 }) {
                matched.insert(entry.path)
                let item = Item(source: entry.track.path, destination: entry.path, size: entry.track.fileSize, replacing: path)
                if manifest.contains(path) { scan.moved.append(item) } else { scan.foundElsewhere.append(item) }
            } else if manifest.contains(path) {
                scan.unneeded.append(path)
            } else {
                scan.otherFiles += 1
            }
        }
        // Playlist files MacBee wrote for playlists that aren't chosen any more.
        scan.unneeded += previousManifest.filter {
            $0.hasPrefix(playlistFolder + "/") && scan.playlists[$0] == nil && existing[$0] != nil
        }.sorted()
        for entry in missing where !matched.contains(entry.path) {
            scan.newSongs.append(Item(source: entry.track.path, destination: entry.path, size: entry.track.fileSize))
        }
        return scan
    }

    /// The operations for a scan and the chosen options, plus the playlist files.
    public static func job(for scan: Scan, choices: Choices, device: String) -> Job {
        var operations: [Operation] = []
        var keptElsewhere: [String: String] = [:] // wanted path -> the other file kept in its place
        if choices.copyNew { operations += scan.newSongs.map { .copy($0, .new) } }
        if choices.replaceChanged {
            operations += scan.changed.map { .copy($0, .replace) }
            for item in scan.moved {
                operations.append(.copy(item, .move))
                if let old = item.replacing { operations.append(.remove(old)) }
            }
        }
        for item in scan.foundElsewhere {
            switch choices.elsewhere {
            case .replace:
                operations.append(.copy(item, .elsewhereReplace))
                if let old = item.replacing { operations.append(.remove(old)) }
            case .keepBoth:
                operations.append(.copy(item, .elsewhereKeepBoth))
            case .skip:
                if let old = item.replacing { keptElsewhere[item.destination] = old }
            }
        }
        if choices.removeUnneeded { operations += scan.unneeded.map { .remove($0) } }

        var playlists: [String: String] = [:]
        for (file, lines) in scan.playlists {
            var text = ["#EXTM3U"]
            for line in lines {
                text.append("#EXTINF:\(line.info)")
                text.append("../" + (keptElsewhere[line.path] ?? line.path))
            }
            playlists[file] = text.joined(separator: "\n") + "\n"
        }
        return Job(device: device, operations: operations, playlists: playlists, manifest: scan.previousManifest)
    }

    /// Does one operation and records it in the job's report and manifest. Copies go to a temporary name first,
    /// so a copy cut short (unplugged, stopped) never leaves half a song under the real name.
    public static func perform(_ operation: Operation, in job: inout Job) throws {
        let fm = FileManager.default
        let device = URL(fileURLWithPath: job.device)
        switch operation {
        case let .copy(item, kind):
            let target = device.appendingPathComponent(item.destination)
            let partial = target.appendingPathExtension("macbee-part")
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: partial.path) { try fm.removeItem(at: partial) }
            try fm.copyItem(at: URL(fileURLWithPath: item.source), to: partial)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: partial, to: target)
            if !job.manifest.contains(item.destination) { job.manifest.append(item.destination) }
            job.report.bytes += item.size
            switch kind {
            case .new: job.report.copiedNew += 1
            case .replace: job.report.replaced += 1
            case .move: job.report.moved += 1
            case .elsewhereReplace: job.report.replacedElsewhere += 1
            case .elsewhereKeepBoth: job.report.keptBoth += 1
            }
        case let .remove(path):
            let target = device.appendingPathComponent(path)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            job.manifest.removeAll { $0 == path }
            // Moves and replacements are counted with their copy; only songs no longer needed count here.
            let partOfCopy = job.operations.contains {
                if case let .copy(item, _) = $0 { return item.replacing == path }
                return false
            }
            if !partOfCopy { job.report.removed += 1 }
            removeEmptyFolders(from: target.deletingLastPathComponent(), upTo: device)
        }
    }

    /// Writes the playlist files and MacBee's record of what it put on the device.
    public static func finish(_ job: Job) {
        let device = URL(fileURLWithPath: job.device)
        for (path, text) in job.playlists {
            let target = device.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: target, atomically: true, encoding: .utf8)
        }
        saveManifest(job)
    }

    public static func saveManifest(_ job: Job) {
        let device = URL(fileURLWithPath: job.device)
        let manifest = Set(job.manifest).union(job.playlists.keys).sorted()
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: device.appendingPathComponent(manifestName))
        }
    }

    /// What's on the device now (relative path -> size and date) and what MacBee put there last time.
    public static func inspect(_ device: URL) -> (existing: [String: FileInfo], manifest: [String]) {
        let manifest = (try? Data(contentsOf: device.appendingPathComponent(manifestName)))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        var existing: [String: FileInfo] = [:]
        let base = device.standardizedFileURL.path
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey]
        if let walker = FileManager.default.enumerator(at: device, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true, url.pathExtension != "macbee-part" else { continue }
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(base + "/") else { continue }
                existing[String(path.dropFirst(base.count + 1))] =
                    FileInfo(size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast)
            }
        }
        return (existing, manifest)
    }

    /// A device song's key and length from its tags (for spotting the same song under another name).
    public static func identify(fileAt url: URL) -> (key: String, seconds: Double)? {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url) else { return nil }
        let m = file.metadata
        guard let title = m.title, !title.isEmpty else { return nil }
        return (songKey(artist: m.artist, title: title, album: m.albumTitle), file.properties.duration ?? 0)
    }

    /// Characters most players and file systems (FAT32, exFAT) reject become "_".
    static func safe(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        var cleaned = String(name.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) })
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if cleaned.isEmpty { cleaned = "_" }
        return String(cleaned.prefix(120))
    }

    private static func removeEmptyFolders(from folder: URL, upTo device: URL) {
        var current = folder.standardizedFileURL
        let stop = device.standardizedFileURL.path
        while current.path.hasPrefix(stop + "/"),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: current.path),
              contents.filter({ $0 != ".DS_Store" }).isEmpty {
            try? FileManager.default.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }
}
