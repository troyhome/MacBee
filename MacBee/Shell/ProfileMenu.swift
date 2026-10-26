import SwiftUI

/// The sidebar's title: "MacBee", and when there's more than one profile, whose MacBee it is with a menu to switch.
struct ProfileMenu: View {
    @Environment(\.theme) private var theme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let profiles = Profiles.all
        if profiles.count > 1 {
            Menu {
                ForEach(profiles) { profile in
                    Button {
                        if profile.id != Profiles.activeId { Profiles.switchTo(profile.id) }
                    } label: {
                        if profile.id == Profiles.activeId { Label(profile.name, systemImage: "checkmark") } else { Text(profile.name) }
                    }
                }
                Divider()
                Button("Manage Profiles…") {
                    UserDefaults.standard.set("general", forKey: "preferencesTab")
                    openSettings()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("MacBee")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    Text(Profiles.active.name)
                        .font(.mbSecondary)
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch to another person's profile (MacBee restarts)")
        } else {
            Text("MacBee")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.textPrimary)
        }
    }
}
