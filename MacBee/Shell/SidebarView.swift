import SwiftUI

/// Collapsible sidebar: compact by default, icons only when collapsed.
struct SidebarView: View {
    @Binding var selection: SidebarItem
    @AppStorage("sidebarCollapsed") private var collapsed = false
    @Environment(\.theme) private var theme
    @Environment(PreferencesStore.self) private var preferences
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            SidebarSearchField(collapsed: $collapsed)
                .padding(.bottom, 8)
            ForEach(SidebarItem.library) { item in
                SidebarRow(item: item, isSelected: isSelected(item), collapsed: collapsed) {
                    app.go(to: item)
                }
            }
            if collapsed {
                // Playlists stay reachable as small pictures; hover for the name.
                CollapsedPlaylistIcons()
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                PlaylistSidebarSection()
                    .padding(.top, 14)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            SidebarRow(item: .playlistStudio, isSelected: selection == .playlistStudio, collapsed: collapsed) {
                app.toggleStudio()
            }
            .help(app.isInStudio ? "Leave Playlist Studio" : "Open Playlist Studio")
            LibrarySourceStatus(collapsed: collapsed)
                .padding(.horizontal, 18)
                .padding(.top, 2)
            ScanStatusView(collapsed: collapsed)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .padding(.vertical, 10)
        .frame(width: collapsed ? Metrics.sidebarCollapsedWidth : preferences.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(theme.sidebar)
    }

    private var header: some View {
        HStack {
            if !collapsed {
                Text("MacBee")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { collapsed.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collapsed ? "Expand sidebar" : "Collapse sidebar")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, collapsed ? 0 : 18)
        .padding(.bottom, 8)
    }

    /// "Playlists" is highlighted only on the all-playlists page; a single playlist highlights its own row.
    private func isSelected(_ item: SidebarItem) -> Bool {
        item == .playlists ? selection == .playlists && app.selectedPlaylistId == nil : selection == item
    }
}
