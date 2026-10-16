import Foundation
import MacBeeLibrary

/// Opens songs in an external tag editor. Implemented by ExternalTagEditor (TagBee).
@MainActor
protocol TagEditorService {
    func edit(_ tracks: [Track]) async throws
}

/// Plex sign-in. Implemented by PlexConnection (the away-from-home route to the same library).
@MainActor
protocol PlexService {
    var isSignedIn: Bool { get }
    func signIn() async throws
    func signOut()
}
