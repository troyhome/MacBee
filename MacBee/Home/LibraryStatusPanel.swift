import AppKit
import MacBeeLibrary
import SwiftUI

/// Scan/Refresh button, scan progress (no animation), last scan, folder status, last scan summary.
struct LibraryStatusPanel: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var folderError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    library.scanAll()
                } label: {
                    Label("Scan Library", systemImage: "arrow.clockwise")
                }
                .disabled(library.isScanning)
                Button("Add Folder…", action: chooseFolder)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }

            ForEach(library.folders) { FolderStatusRow(state: $0) }

            if let summary = lastScanSummary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            if let error = folderError ?? library.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.warning)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    /// "Checking 2 Set Music…", "Reading 120 of 300", or "Last checked Today at 9:41 PM".
    private var statusText: String {
        if let progress = library.scanProgress {
            switch progress.phase {
            case .checking: return "Checking \(progress.folderName)…"
            case .reading: return "Reading \(progress.done) of \(progress.total) new or changed files…"
            case .finishing: return "Finishing…"
            }
        }
        guard let last = library.folders.compactMap(\.folder.lastScanAt).max() else { return "Not scanned yet" }
        return "Last checked \(Format.relativeDateTime(last))"
    }

    /// Summary of the last scan, only when something changed.
    private var lastScanSummary: String? {
        let reports = library.lastReports
        guard !reports.isEmpty else { return nil }
        let added = reports.map(\.added).reduce(0, +)
        let updated = reports.map(\.updated).reduce(0, +)
        let missing = reports.map(\.missing).reduce(0, +)
        let failed = reports.map(\.failedCount).reduce(0, +)
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if updated > 0 { parts.append("\(updated) updated") }
        if missing > 0 { parts.append("\(missing) missing") }
        if failed > 0 { parts.append("\(failed) couldn't be read") }
        if reports.contains(where: \.wasOffline) { parts.append("a folder was offline, nothing changed there") }
        return parts.isEmpty ? "Last scan: no changes." : "Last scan: " + parts.joined(separator: ", ") + "."
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await library.addFolder(url)
                folderError = nil
            } catch {
                folderError = error.localizedDescription
            }
        }
    }
}

private struct FolderStatusRow: View {
    let state: MusicLibrary.FolderState
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isNetwork ? "externaldrive.connected.to.line.below" : "folder")
                .foregroundStyle(theme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.folder.path)
                    .foregroundStyle(theme.textPrimary)
                Text(state.isNetwork ? "Network drive" : "On this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            Text(state.isOnline ? "Connected" : "Not connected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.isOnline ? theme.good : theme.warning)
        }
        .font(.system(size: 13))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface))
    }
}
