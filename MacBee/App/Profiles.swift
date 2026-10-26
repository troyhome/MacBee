import AppKit
import Foundation
import MacBeeLibrary

/// People who use MacBee on this Mac: each profile has its own favorites, ratings, plays, playlists, saved mixes,
/// video progress and likes, over the same music and video folders. Switching restarts MacBee with that profile.
///
/// The first profile ("main") uses the files MacBee always used; others live in Application Support > MacBee >
/// Profiles > <id> (their own Library.sqlite; covers are shared). Per-person settings stored in UserDefaults go
/// through `Profiles.key(_:)`, which leaves the main profile's keys as they were.
enum Profiles {
    struct Profile: Codable, Identifiable, Hashable {
        var id: String
        var name: String
    }

    static let mainId = "main"

    static var all: [Profile] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "profiles"),
                  let saved = try? JSONDecoder().decode([Profile].self, from: data), !saved.isEmpty
            else { return [Profile(id: mainId, name: NSFullUserName().split(separator: " ").first.map(String.init) ?? "Me")] }
            return saved
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "profiles") }
    }

    /// Fixed for the whole run: switching relaunches the app.
    static let activeId: String = {
        let id = UserDefaults.standard.string(forKey: "activeProfile") ?? mainId
        return all.contains { $0.id == id } ? id : mainId
    }()

    static var active: Profile { all.first { $0.id == activeId } ?? all[0] }

    /// A per-person UserDefaults key (the main profile keeps the plain key).
    static func key(_ base: String) -> String {
        activeId == mainId ? base : "\(base).\(activeId)"
    }

    static var baseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBee", isDirectory: true)
    }

    /// Where the active profile keeps its own files (library database, sync notes, remembered songs).
    static var directory: URL { directory(for: activeId) }

    static func directory(for id: String) -> URL {
        id == mainId ? baseDirectory : baseDirectory.appendingPathComponent("Profiles/\(id)", isDirectory: true)
    }

    static var libraryLocation: LibraryLocation {
        activeId == mainId ? .default
            : LibraryLocation(databaseDirectory: directory, artworkDirectory: baseDirectory.appendingPathComponent("Artwork", isDirectory: true))
    }

    // MARK: - Managing

    /// Makes a new profile: a copy of this library's folders and songs, with none of this person's own data.
    static func create(named name: String, from library: MusicLibrary) async throws -> Profile {
        let profile = Profile(id: UUID().uuidString.prefix(8).lowercased(), name: name)
        let folder = directory(for: profile.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await library.database.copyWithoutPersonalData(to: folder.appendingPathComponent("Library.sqlite"))
        all = all + [profile]
        return profile
    }

    static func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        all = all.map { $0.id == id ? Profile(id: $0.id, name: trimmed) : $0 }
    }

    /// Removes a profile (not the main one, not the one in use). Its folder goes to the Trash.
    static func delete(_ id: String) {
        guard id != mainId, id != activeId else { return }
        all = all.filter { $0.id != id }
        try? FileManager.default.trashItem(at: directory(for: id), resultingItemURL: nil)
    }

    /// Restarts MacBee using another profile.
    static func switchTo(_ id: String) {
        UserDefaults.standard.set(id, forKey: "activeProfile")
        // A fresh copy of MacBee starts with the new profile, then this one quits (works in the App Store sandbox too).
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
