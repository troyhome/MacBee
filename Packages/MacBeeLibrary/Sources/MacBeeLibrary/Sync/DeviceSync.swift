import Foundation

/// Copies playlists to a music player or drive (roadmap Phase 4): songs go to Artist/Album/## - Title.ext,
/// each playlist gets an .m3u8 next to the music, and only what changed is copied. Songs MacBee put there
/// earlier that no playlist needs any more are removed; files MacBee didn't put there are never touched.
public enum DeviceSync {
    /// One playlist (or smart playlist / saved mix) to put on the device.
    public struct Source: Sendable {
        public var name: String
        public var tracks: [Track]
        public init(name: String, tracks: [Track]) {
            self.name = name
            self.tracks = tracks
        }
    }

    public struct Plan: Sendable, Equatable {
        /// Library file -> where it goes on the device (relative to the device folder).
        public var copies: [(source: String, destination: String)] = []
        /// Files already there and unchanged.
        public var unchanged = 0
        /// Files MacBee put there before that aren't needed now (relative paths).
        public var removals: [String] = []
        /// Playlist files to write: relative path -> text.
        public var playlists: [String: String] = [:]
        /// Everything MacBee will have put on the device after this sync (for the next sync's removals).
        public var manifest: [String] = []

        public static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.copies.map { $0.source + "→" + $0.destination } == rhs.copies.map { $0.source + "→" + $0.destination }
                && lhs.unchanged == rhs.unchanged && lhs.removals == rhs.removals && lhs.playlists == rhs.playlists
        }
    }

    public struct Result: Sendable {
        public var copied = 0
        public var unchanged = 0
        public var removed = 0
        public var failed: [String] = []
    }

    /// MacBee's record of what it put on the device.
    public static let manifestName = ".macbee-sync.json"
    public static let playlistFolder = "Playlists"

    /// Where a song goes on the device: "Artist/Album/03 - Title.flac" (disc number first for multi-disc albums).
    public static func devicePath(for track: Track) -> String {
        let artist = safe(track.displayAlbumArtist.isEmpty ? (track.artist ?? "Unknown Artist") : track.displayAlbumArtist)
        let album = safe(track.displayAlbum.isEmpty ? "Unknown Album" : track.displayAlbum)
        var number = track.trackNumber.map { String(format: "%02d", $0) } ?? "00"
        if let disc = track.discNumber, (track.discTotal ?? 1) > 1 { number = "\(disc)-\(number)" }
        let ext = (track.path as NSString).pathExtension.lowercased()
        return "\(artist)/\(album)/\(number) - \(safe(track.displayTitle)).\(ext)"
    }

    /// Works out what to copy and remove. `existing` is what's on the device now (relative path -> size),
    /// `previousManifest` what MacBee put there last time.
    public static func plan(sources: [Source], existing: [String: Int64], previousManifest: [String]) -> Plan {
        var plan = Plan()
        var wanted: [String: Track] = [:]
        for source in sources {
            var lines = ["#EXTM3U"]
            for track in source.tracks {
                let path = devicePath(for: track)
                wanted[path] = wanted[path] ?? track
                lines.append("#EXTINF:\(Int(track.duration.rounded())),\(track.displayArtist) - \(track.displayTitle)")
                lines.append("../" + path)
            }
            plan.playlists["\(playlistFolder)/\(safe(source.name)).m3u8"] = lines.joined(separator: "\n") + "\n"
        }
        for (path, track) in wanted.sorted(by: { $0.key < $1.key }) {
            if existing[path] == track.fileSize {
                plan.unchanged += 1
            } else {
                plan.copies.append((track.path, path))
            }
        }
        let keep = Set(wanted.keys).union(plan.playlists.keys)
        plan.removals = previousManifest.filter { !keep.contains($0) && existing[$0] != nil }.sorted()
        plan.manifest = keep.sorted()
        return plan
    }

    /// Does the plan. `progress` gets (done, total) after each file. Stops early if the task is cancelled.
    public static func run(_ plan: Plan, to device: URL,
                           progress: @Sendable (Int, Int) -> Void = { _, _ in }) -> Result {
        let fm = FileManager.default
        var result = Result()
        result.unchanged = plan.unchanged
        let total = plan.copies.count + plan.removals.count
        var done = 0
        for copy in plan.copies {
            if Task.isCancelled { break }
            let target = device.appendingPathComponent(copy.destination)
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: URL(fileURLWithPath: copy.source), to: target)
                result.copied += 1
            } catch {
                result.failed.append(copy.destination)
            }
            done += 1
            progress(done, total)
        }
        for removal in plan.removals {
            if Task.isCancelled { break }
            let target = device.appendingPathComponent(removal)
            if (try? fm.removeItem(at: target)) != nil { result.removed += 1 }
            removeEmptyFolders(from: target.deletingLastPathComponent(), upTo: device)
            done += 1
            progress(done, total)
        }
        for (path, text) in plan.playlists {
            let target = device.appendingPathComponent(path)
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? text.write(to: target, atomically: true, encoding: .utf8)) == nil { result.failed.append(path) }
        }
        if let data = try? JSONEncoder().encode(plan.manifest) {
            try? data.write(to: device.appendingPathComponent(manifestName))
        }
        return result
    }

    /// What's on the device now (relative path -> size) and what MacBee put there last time.
    public static func inspect(_ device: URL) -> (existing: [String: Int64], manifest: [String]) {
        let manifest = (try? Data(contentsOf: device.appendingPathComponent(manifestName)))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        var existing: [String: Int64] = [:]
        let base = device.standardizedFileURL.path
        if let walker = FileManager.default.enumerator(at: device, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                       options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(base + "/") else { continue }
                existing[String(path.dropFirst(base.count + 1))] = Int64(values?.fileSize ?? 0)
            }
        }
        return (existing, manifest)
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
