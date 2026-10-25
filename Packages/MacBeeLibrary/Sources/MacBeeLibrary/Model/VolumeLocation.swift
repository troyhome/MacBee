import Foundation

/// Finds a folder on a drive wherever macOS mounts that drive.
///
/// macOS can mount the same drive at a different place, e.g. "/Volumes/2 Set Music-1" after a connection died and
/// left an empty "/Volumes/2 Set Music" behind, or under ~/MountPoints when another app mounts the share. So
/// folders on drives also remember which drive they're on (`volumeID`) and where on it (`pathInVolume`).
public enum VolumeLocation {

    /// "smb://crusher/music" for a network share (no user name), "uuid:…" for a local drive.
    /// Nil for folders on the Mac's own disk.
    public static func identify(_ path: String) -> (volumeID: String, pathInVolume: String)? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeURLForRemountingKey,
                                                             .volumeUUIDStringKey]),
              let volume = values.volume?.standardizedFileURL.path, volume != "/" else { return nil }
        let id: String
        if let remote = values.volumeURLForRemounting, let normalized = normalize(remote) {
            id = normalized
        } else if let uuid = values.volumeUUIDString {
            id = "uuid:" + uuid
        } else {
            return nil
        }
        let inside = path == volume ? "" : String(path.dropFirst(volume.count + 1))
        return (id, inside)
    }

    /// The folder is there and readable, on its own drive: not an empty folder left in /Volumes by a drive that
    /// went away, nor another drive that took the same name.
    public static func isConnected(_ path: String, volumeID: String?) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            && isDir.boolValue
            && FileManager.default.isReadableFile(atPath: path)
            && !isLeftoverMountPoint(path)
            && isOnVolume(path, volumeID: volumeID)
    }

    /// An empty folder left in /Volumes by a drive that went away. It isn't the drive, even though it exists.
    public static func isLeftoverMountPoint(_ path: String) -> Bool {
        guard path.hasPrefix("/Volumes/") else { return false }
        let volume = try? URL(fileURLWithPath: path, isDirectory: true).resourceValues(forKeys: [.volumeURLKey]).volume
        return volume?.standardizedFileURL.path == "/"
    }

    /// True when the folder at `path` is on the drive `volumeID` (or the drive is unknown).
    public static func isOnVolume(_ path: String, volumeID: String?) -> Bool {
        guard let volumeID else { return true }
        guard let here = identify(path)?.volumeID else { return false }
        return sameVolume(here, volumeID)
    }

    /// Where that folder is right now, if its drive is mounted somewhere.
    public static func currentPath(volumeID: String, pathInVolume: String) -> String? {
        let keys: [URLResourceKey] = [.volumeURLForRemountingKey, .volumeUUIDStringKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        // Same server first; then the same share reached another way (an IP address instead of a name).
        var fallback: String?
        for volume in volumes {
            guard let values = try? volume.resourceValues(forKeys: Set(keys)) else { continue }
            let id = values.volumeURLForRemounting.flatMap(normalize) ?? values.volumeUUIDString.map { "uuid:" + $0 }
            guard let id, sameVolume(id, volumeID) else { continue }
            let root = volume.standardizedFileURL.path
            let candidate = pathInVolume.isEmpty ? root : root + "/" + pathInVolume
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue else { continue }
            if id == volumeID { return candidate }
            fallback = fallback ?? candidate
        }
        return fallback
    }

    /// For folders whose drive isn't known yet: "/Volumes/2 Set Music/…" when the drive is now mounted as
    /// "/Volumes/2 Set Music-1" (macOS adds a number when an empty folder was left behind under the old name).
    public static func renumberedMountPath(of path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        let name = String(parts[1]), inside = parts.dropFirst(2).joined(separator: "/")
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        for volume in volumes {
            let root = volume.standardizedFileURL.path
            guard root.hasPrefix("/Volumes/" + name + "-"),
                  root.dropFirst(("/Volumes/" + name + "-").count).allSatisfy(\.isNumber) else { continue }
            let candidate = inside.isEmpty ? root : root + "/" + inside
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue { return candidate }
        }
        return nil
    }

    // MARK: - Helpers

    /// scheme://host/share, lowercased, without user name, password or port; ".local" names count as the same host.
    static func normalize(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), var host = url.host?.lowercased() else { return nil }
        for suffix in ["._smb._tcp.local", "._afpovertcp._tcp.local", ".local"] where host.hasSuffix(suffix) {
            host = String(host.dropLast(suffix.count))
        }
        let share = url.path.removingPercentEncoding?.lowercased() ?? url.path.lowercased()
        return scheme + "://" + host + (share.hasSuffix("/") ? String(share.dropLast()) : share)
    }

    /// The same drive: equal IDs, or the same share on a server reached by another name (or its IP address).
    static func sameVolume(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard let pa = shareParts(a), let pb = shareParts(b) else { return false }
        return pa.scheme == pb.scheme && !pa.share.isEmpty && pa.share == pb.share
    }

    /// "smb://host/share" -> ("smb", "share"). Nil for local drives ("uuid:…").
    private static func shareParts(_ id: String) -> (scheme: Substring, share: Substring)? {
        guard let separator = id.range(of: "://") else { return nil }
        let rest = id[separator.upperBound...]
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        return (id[..<separator.lowerBound], rest[rest.index(after: slash)...])
    }
}
