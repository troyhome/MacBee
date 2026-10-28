import AppKit
import MacBeeLibrary

/// Hands songs to MD Deck (Troy's MiniDisc app): they open on its Disc page, in order, ready to send to the recorder.
enum MDDeckSender {
    static let bundleIdentifier = "com.troyhomenchuk.MDDeck"

    /// MD Deck, if it's installed.
    static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }

    /// Opens the songs' files in MD Deck. Songs whose file can't be reached right now (drive away) are left out;
    /// returns a note about them, or nil when all went.
    @MainActor
    @discardableResult
    static func send(_ tracks: [Track]) -> String? {
        guard let app = appURL else { return "MD Deck isn't installed on this Mac." }
        let files = tracks.map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
        if !files.isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration)
        }
        let missing = tracks.count - files.count
        return missing == 0 ? nil : "\(missing) of the songs weren't sent because their files can't be reached right now."
    }
}
