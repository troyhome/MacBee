import SwiftUI

/// Full-width bar at the bottom of the window.
/// Each part is its own view, so the 4-times-a-second progress updates only redraw the scrubber.
struct PlayBarView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 20) {
            NowPlayingInfoView()
                .frame(width: 250, alignment: .leading)
            VStack(spacing: 2) {
                TransportControls()
                ScrubberRow()
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            OutputControls()
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: Metrics.playBarHeight)
        .background(theme.bar)
        .secondaryClickPlaysPauses()
    }
}
