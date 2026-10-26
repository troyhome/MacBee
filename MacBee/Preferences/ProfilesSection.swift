import MacBeeLibrary
import SwiftUI

/// Settings > General > Profiles: one per person, each with their own favorites, plays, playlists, mixes and
/// video progress over the same music. Switching restarts MacBee.
struct ProfilesSection: View {
    @Environment(AppModel.self) private var app
    @State private var profiles = Profiles.all
    @State private var newName = ""
    @State private var renaming: Profiles.Profile?
    @State private var renameText = ""
    @State private var deleting: Profiles.Profile?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Section(header: PreferenceHeader("Profiles")) {
            ForEach(profiles) { profile in
                HStack(spacing: 10) {
                    Image(systemName: profile.id == Profiles.activeId ? "person.crop.circle.fill" : "person.crop.circle")
                        .foregroundStyle(profile.id == Profiles.activeId ? Color.accentColor : .secondary)
                    Text(profile.name)
                    if profile.id == Profiles.activeId {
                        Text("In use").font(.mbCaption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if profile.id != Profiles.activeId {
                        Button("Switch") { Profiles.switchTo(profile.id) }
                    }
                    Button("Rename…") { renameText = profile.name; renaming = profile }
                    if profile.id != Profiles.mainId && profile.id != Profiles.activeId {
                        Button("Delete…") { deleting = profile }
                    }
                }
            }
            HStack {
                TextField("New profile name", text: $newName)
                Button(busy ? "Adding…" : "Add Profile") { add() }
                    .disabled(busy || newName.trimmingCharacters(in: .whitespaces).isEmpty || app.library == nil)
            }
            PreferenceNote("A profile per person: each has their own favorites, ratings, plays, playlists, saved mixes, and video progress and likes, over the same music and video folders. Switching restarts MacBee. Device Sync only syncs a profile with the profile of the same name on your other Mac.")
            if let message { PreferenceNote(message) }
        }
        .alert("Rename Profile", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let profile = renaming { Profiles.rename(profile.id, to: renameText); profiles = Profiles.all }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete the profile “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Profile", role: .destructive) {
                if let profile = deleting { Profiles.delete(profile.id); profiles = Profiles.all }
            }
        } message: {
            Text("Their favorites, plays, playlists and mixes go to the Trash with the profile. Your music isn't touched.")
        }
    }

    private func add() {
        guard let library = app.library else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        busy = true
        Task {
            do {
                let profile = try await Profiles.create(named: name, from: library)
                profiles = Profiles.all
                newName = ""
                message = "Added \(profile.name). Click Switch to use it."
            } catch {
                message = "Couldn't add the profile. \(error.localizedDescription)"
            }
            busy = false
        }
    }
}
