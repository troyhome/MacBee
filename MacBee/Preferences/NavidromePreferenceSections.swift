import SwiftUI

/// Navidrome (or any Subsonic server) in the Library tab of Settings: connect, match songs, disconnect.
/// These are Form sections; the Library tab's Form holds them.
struct NavidromePreferenceSections: View {
    @Bindable var navidrome: NavidromeConnection
    @Environment(\.theme) private var theme
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connecting = false

    var body: some View {
        Section("Navidrome") {
            if navidrome.isSetUp {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(navidrome.username) on \(navidrome.serverAddress)")
                        Text(navidrome.isConnected ? "Connected" : "Can't reach the server right now")
                            .font(.mbCaption)
                            .foregroundStyle(navidrome.isConnected ? theme.good : theme.warning)
                    }
                    Spacer()
                    Button("Check Connection") { Task { await navidrome.check() } }
                    Button("Disconnect") { navidrome.disconnect() }
                }
                HStack {
                    Text(navidrome.isMatching ? "Matching songs with Navidrome…"
                         : "\(navidrome.linkedCount.formatted()) songs can play from Navidrome")
                    Spacer()
                    Button("Match Again") { Task { await navidrome.matchLibrary() } }
                        .disabled(navidrome.isMatching)
                }
                PreferenceNote("Songs are matched by folder and file name when the server reports real paths (Navidrome: turn on Report Real Path for the MacBee player), otherwise by artist, title, album and length. Match again after adding music.")
            } else {
                TextField("Server address", text: $address, prompt: Text("http://192.168.1.10:4533"))
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                HStack {
                    PreferenceNote("Works with Navidrome and other Subsonic servers (Gonic, Airsonic, Ampache). Songs are fetched as original files, never converted.")
                    Spacer()
                    Button(connecting ? "Connecting…" : "Connect") {
                        connecting = true
                        Task {
                            await navidrome.connect(address: address, username: username, password: password)
                            if navidrome.isSetUp { password = "" }
                            connecting = false
                        }
                    }
                    .disabled(connecting || address.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
            if let message = navidrome.message {
                PreferenceNote(message)
            }
        }
    }
}
