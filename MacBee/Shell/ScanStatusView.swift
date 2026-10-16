import MacBeeLibrary
import SwiftUI

/// Small "checking library" indicator at the bottom of the sidebar.
struct ScanStatusView: View {
    let collapsed: Bool
    @Environment(MusicLibrary.self) private var library
    @Environment(\.theme) private var theme

    var body: some View {
        if let progress = library.scanProgress {
            // No moving parts: just text, plus a plain bar once there's a count to show.
            if collapsed {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .help(text(for: progress))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text(for: progress))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if progress.total > 0 {
                        ProgressView(value: progress.fraction)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func text(for progress: ScanProgress) -> String {
        switch progress.phase {
        case .checking: "Checking \(progress.folderName)…"
        case .reading: "Reading \(progress.done) of \(progress.total)"
        case .finishing: "Finishing…"
        }
    }
}
