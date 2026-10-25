import SwiftUI

/// Search box at the top of the sidebar (⌘F). Typing shows the Search page.
/// When the sidebar is collapsed it becomes an icon that expands the sidebar.
struct SidebarSearchField: View {
    @Binding var collapsed: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if collapsed {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { collapsed = false }
                    focusSoon()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Search (⌘F)")
            } else {
                field
            }
        }
        .onChange(of: model.searchFocusRequest) {
            if collapsed { withAnimation(.easeOut(duration: 0.15)) { collapsed = false } }
            focusSoon()
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.mbSecondary)
                .foregroundStyle(theme.textTertiary)
            TextField("Search", text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .focused($focused)
                .onSubmit { showResults() }
                .onChange(of: model.searchText) { showResults() }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.mbSecondary)
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? theme.accent.opacity(0.7) : .clear, lineWidth: 1))
        .padding(.horizontal, 12)
    }

    private func showResults() {
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty { model.selection = .search }
    }

    /// The field only exists after the sidebar expands, so focus it on the next run loop.
    private func focusSoon() {
        DispatchQueue.main.async { focused = true }
    }
}
