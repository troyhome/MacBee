// macbee-library — Terminal tool for testing the Phase 2 library.
//
//   swift run macbee-library add "/Volumes/2 Set Music"   add a folder and scan it
//   swift run macbee-library scan                          check all folders for changes
//   swift run macbee-library stats                         totals (artists, albums, tracks, time)
//   swift run macbee-library folders                       watched folders and their status
//   swift run macbee-library albums [count]                newest albums first
//   swift run macbee-library artists                       all album artists
//   swift run macbee-library search <text>                 find tracks
//   swift run macbee-library watch                         keep running; rescan on changes
//   swift run macbee-library remove "/Volumes/2 Set Music" remove a folder from the library
//
// Uses the same library location the app will use (~/Library/Application Support/MacBee),
// so the first full scan only has to happen once.

import Foundation
import MacBeeLibrary

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let days = total / 86_400, hours = (total % 86_400) / 3600, minutes = (total % 3600) / 60
    if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m \(total % 60)s"
}

func printReport(_ r: ScanReport) {
    print("\n\(r.folderPath)")
    if r.wasOffline { print("  Folder not reachable (drive not mounted?). Nothing changed."); return }
    if r.cancelled { print("  Cancelled.") }
    print("  added \(r.added), updated \(r.updated), moved \(r.moved), missing \(r.missing), restored \(r.restored), unchanged \(r.unchanged)")
    if r.skippedRemovals { print("  Folder looked empty, so no tracks were marked missing.") }
    if r.failedCount > 0 {
        print("  \(r.failedCount) file(s) couldn't be read, e.g.:")
        r.failedPaths.prefix(5).forEach { print("    \($0)") }
    }
    print("  took \(formatDuration(r.seconds))")
}

func printStats(_ s: LibraryStats) {
    print("Artists: \(s.artists)   Albums: \(s.albums)   Tracks: \(s.tracks)   Total time: \(formatDuration(s.totalDuration))")
}

@MainActor
func run() async -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    var location = LibraryLocation.default
    if let i = args.firstIndex(of: "--db"), i + 1 < args.count {
        location = LibraryLocation(directory: URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath))
        args.removeSubrange(i...(i + 1))
    }
    guard let command = args.first else {
        print("Commands: add <folder>, scan, stats, folders, albums [count], artists, search <text>, watch, remove <folder>")
        return 1
    }
    let rest = Array(args.dropFirst())

    let library: MusicLibrary
    do { library = try MusicLibrary(location: location) } catch {
        print("Couldn't open the library: \(error.localizedDescription)"); return 1
    }

    library.eventHandler = { event in
        switch event {
        case let .scanProgress(p):
            switch p.phase {
            case .checking: print("\r\(p.folderName): checking files... \(p.filesFound) found", terminator: "")
            case .reading: print("\r\(p.folderName): reading tags \(p.done) of \(p.total)        ", terminator: "")
            case .finishing: print("\r\(p.folderName): finishing...                        ", terminator: "")
            }
            fflush(stdout)
        case let .scanFinished(reports):
            reports.forEach(printReport)
        case let .error(message):
            print("\n! \(message)")
        case .foldersChanged:
            break
        }
    }

    switch command {
    case "add":
        guard let path = rest.first else { print("Usage: add <folder>"); return 1 }
        do {
            try await library.addFolder(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        } catch {
            print(error.localizedDescription); return 1
        }
        await library.waitForScans()
        await library.refreshStats()
        print(""); printStats(library.stats)

    case "scan":
        await library.start(watch: false)
        await library.waitForScans()
        await library.refreshStats()
        print(""); printStats(library.stats)

    case "stats":
        await library.refreshStats()
        printStats(library.stats)

    case "folders":
        let folders = (try? await library.database.folders()) ?? []
        if folders.isEmpty { print("No folders yet. Use: add <folder>") }
        for f in folders {
            let status = f.isReachable ? "online" : "OFFLINE"
            let network = f.isNetwork ? ", network" : ""
            let last = f.lastScanAt.map { "last scanned \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "never scanned"
            print("• \(f.path)  [\(status)\(network)]  \(last)")
        }

    case "albums":
        let count = rest.first.flatMap(Int.init) ?? 25
        let albums = (try? await library.database.albums(sortedBy: .recentlyAdded, limit: count)) ?? []
        for a in albums {
            let year = a.year.map { " (\($0))" } ?? ""
            var format = ""
            if let bits = a.maxBitDepth, let rate = a.maxSampleRate, bits > 1 {
                format = "  \(bits)/\(rate.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(rate / 1000))" : String(format: "%.1f", rate / 1000))"
            }
            let art = a.artworkId == nil ? "  [no cover]" : ""
            print("• \(a.artist) — \(a.title)\(year)  ·  \(a.trackCount) tracks, \(formatDuration(a.duration))\(format)\(art)")
        }

    case "artists":
        let artists = (try? await library.database.artists()) ?? []
        for a in artists { print("• \(a.name)  (\(a.albumCount) albums, \(a.trackCount) tracks)") }
        print("\(artists.count) artists")

    case "search":
        let text = rest.joined(separator: " ")
        let tracks = (try? await library.database.search(text)) ?? []
        for t in tracks {
            print("• \(t.displayArtist) — \(t.displayTitle)  [\(t.displayAlbum)]  \(t.formatSummary)")
        }
        print("\(tracks.count) result(s)")

    case "remove":
        guard let path = rest.first else { print("Usage: remove <folder>"); return 1 }
        let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        guard let folder = try? await library.database.folders().first(where: { $0.path == target }),
              let id = folder.id else { print("Not in the library: \(target)"); return 1 }
        do { try await library.removeFolder(id: id) } catch { print(error.localizedDescription); return 1 }
        print("Removed \(target) from the library (files on disk untouched).")

    case "watch":
        print("Watching for changes. Press Control-C to stop.")
        await library.start(watch: true)
        // Keep running; scans are triggered by the folder monitor.
        while true { try? await Task.sleep(for: .seconds(3600)) }

    default:
        print("Unknown command: \(command)")
        return 1
    }
    return 0
}

Task { @MainActor in
    exit(await run())
}
dispatchMain()
