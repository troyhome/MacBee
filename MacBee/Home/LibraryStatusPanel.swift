import MacBeeLibrary
import SwiftUI

/// Shown under the Media title only when something needs attention: a music folder that isn't connected,
/// or a library problem. Folder management itself lives in Settings > Library.
struct LibraryNotice: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme

    var body: some View {
        if let message {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.warning)
                Text(message)
                    .font(.mbRowTitle)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                LibrarySettingsButton()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.warning.opacity(0.4), lineWidth: 1))
            .frame(maxWidth: 780, alignment: .leading)
        }
    }

    private var message: String? {
        let offline = library.folders.filter { !$0.isOnline && !$0.folder.isPaused }.map(\.folder.name)
        if let first = offline.first {
            return offline.count == 1
                ? "\(first) isn't connected. Its songs are hidden until it's back."
                : "\(offline.count) music folders aren't connected. Their songs are hidden until they're back."
        }
        return library.lastError
    }
}

/// The Library block on the Media page: one line with the scan status, Scan Library and a way to Settings.
struct LibrarySummaryRow: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(statusText)
                .font(.mbSecondary)
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 8)
            Button {
                library.scanAll()
            } label: {
                Label("Scan Library", systemImage: "arrow.clockwise")
            }
            .disabled(library.isScanning)
            LibrarySettingsButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface))
        .frame(maxWidth: 780, alignment: .leading)
    }

    /// "4 music folders · Checking 2 Set Music…" or "… · Last checked Today at 9:41 PM", plus the last scan's changes.
    private var statusText: String {
        let count = library.folders.count
        let folders = "\(count) music folder\(count == 1 ? "" : "s")"
        var status: String
        if let progress = library.scanProgress {
            switch progress.phase {
            case .checking: status = "Checking \(progress.folderName)…"
            case .reading: status = "Reading \(progress.done) of \(progress.total) new or changed files…"
            case .finishing: status = "Finishing…"
            }
        } else if let last = library.folders.compactMap(\.folder.lastScanAt).max() {
            status = "Last checked \(Format.relativeDateTime(last))"
        } else {
            status = "Not scanned yet"
        }
        if library.scanProgress == nil, let changes = lastScanChanges { status += " · \(changes)" }
        return "\(folders) · \(status)"
    }

    private var lastScanChanges: String? {
        let reports = library.lastReports
        let added = reports.map(\.added).reduce(0, +)
        let updated = reports.map(\.updated).reduce(0, +)
        let missing = reports.map(\.missing).reduce(0, +)
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if updated > 0 { parts.append("\(updated) updated") }
        if missing > 0 { parts.append("\(missing) missing") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Opens Settings on the Library tab.
struct LibrarySettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Library Settings…") {
            UserDefaults.standard.set("library", forKey: "preferencesTab")
            openSettings()
        }
    }
}
