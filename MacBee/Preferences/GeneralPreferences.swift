import SwiftUI

struct GeneralPreferences: View {
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section(header: PreferenceHeader("When MacBee opens")) {
                Picker("Show", selection: $preferences.startPage) {
                    ForEach(StartPage.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Check the library for changes", isOn: $preferences.checkLibraryAtLaunch)
                PreferenceNote("Looks for new, changed and removed files. Only sizes and dates are compared, so it's quick even on a network drive.")
            }
            Section(header: PreferenceHeader("Media page")) {
                ForEach(preferences.homeOrder) { kind in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .help("Drag to change the order")
                        Toggle(isOn: Binding(get: { !preferences.homeHidden.contains(kind) }, set: { on in
                            if on { preferences.homeHidden.remove(kind) } else { preferences.homeHidden.insert(kind) }
                        })) {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                    }
                    .draggable(kind.rawValue)
                    .dropDestination(for: String.self) { items, _ in
                        guard let moved = items.first.flatMap(HomeSectionKind.init(rawValue:)), moved != kind,
                              let from = preferences.homeOrder.firstIndex(of: moved),
                              let to = preferences.homeOrder.firstIndex(of: kind) else { return false }
                        var order = preferences.homeOrder
                        order.remove(at: from)
                        order.insert(moved, at: to)
                        preferences.homeOrder = order
                        return true
                    }
                }
                HStack {
                    PreferenceNote("Drag to set the order of the Media page; untick to hide a section.")
                    Spacer()
                    Button("Reset") {
                        preferences.homeOrder = HomeSectionKind.allCases
                        preferences.homeHidden = []
                    }
                }
            }
            Section(header: PreferenceHeader("Playback")) {
                Toggle("Keep playing when a song, album or playlist ends", isOn: $preferences.continuousPlay)
                PreferenceNote("MacBee carries on with a mix made from the last song. Repeat All still repeats instead.")
                Toggle("TV shows: play the next episode automatically", isOn: $preferences.continuousPlayEpisodes)
                Picker("Count a song as played", selection: $preferences.playCountRule) {
                    ForEach(PlayCountRule.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                PreferenceNote("Used for play counts, Recently Played, Most Played and Play History.")
            }
            Section(header: PreferenceHeader("Lyrics")) {
                Toggle("Find missing lyrics online", isOn: $preferences.findLyricsOnline)
                PreferenceNote("When a song without lyrics plays, MacBee looks them up at LRCLIB (a free lyrics library) and saves them as an .lrc file next to the song, so they show in the lyrics panel from then on.")
            }
        }
        .formStyle(.grouped)
    }
}
