import SwiftUI

/// Collapsible sidebar: compact by default, icons only when collapsed.
struct SidebarView: View {
    @Binding var selection: SidebarItem
    @AppStorage("sidebarCollapsed") private var collapsed = false
    @Environment(\.theme) private var theme
    @Environment(PreferencesStore.self) private var preferences
    @Environment(AppModel.self) private var app
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            SidebarSearchField(collapsed: $collapsed)
                .padding(.bottom, 8)
            if player.currentTrack != nil {
                SidebarRow(item: .playingFrom, isSelected: false, collapsed: collapsed) {
                    Task { await app.showPlayingFrom() }
                }
                .help("Go to where the current music was started")
                .padding(.bottom, 4)
            }
            ForEach(SidebarItem.library.filter { $0 != .tags }) { item in
                SidebarRow(item: item, isSelected: isSelected(item), collapsed: collapsed) {
                    app.go(to: item)
                }
            }
            studios
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

    /// Track Studio and Playlist Studio: modes you enter and leave, set apart from the pages above.
    private var studios: some View {
        VStack(alignment: .leading, spacing: 2) {
            if collapsed {
                Rectangle().fill(theme.separator).frame(height: 1).padding(.horizontal, 12).padding(.vertical, 6)
            } else {
                Text("STUDIOS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }
            SidebarRow(item: .tags, isSelected: selection == .tags, collapsed: collapsed) { app.toggleTrackStudio() }
                .help(app.isInTrackStudio ? "Leave Track Studio" : "Open Track Studio")
            SidebarRow(item: .playlistStudio, isSelected: selection == .playlistStudio, collapsed: collapsed) {
                app.toggleStudio()
            }
            .help(app.isInStudio ? "Leave Playlist Studio" : "Open Playlist Studio")
        }
    }

    /// "Playlists" is highlighted only on the all-playlists page; a single playlist highlights its own row.
    private func isSelected(_ item: SidebarItem) -> Bool {
        item == .playlists ? selection == .playlists && app.selectedPlaylistId == nil : selection == item
    }
}
