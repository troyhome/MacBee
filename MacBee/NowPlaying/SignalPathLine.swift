import MacBeeAudio
import SwiftUI

/// "FLAC 24-bit / 96 kHz → MacBook Air Speakers 24-bit / 96 kHz · Bit-Perfect". Hover for details.
struct SignalPathLine: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        let engine = player.engine
        if let format = engine.currentFormat {
            let device = engine.outputDevice?.name ?? "Output"
            let bits = engine.deviceBitDepth.map { "\($0)-bit / " } ?? ""
            let rate = engine.deviceSampleRate > 0 ? AudioFormatInfo.formatRate(engine.deviceSampleRate) : ""
            let isBitPerfect = engine.signalPath?.isBitPerfect == true
            HStack(spacing: 8) {
                Text("\(format.displayString)  →  \(device) \(bits)\(rate)")
                    .foregroundStyle(.white.opacity(0.75))
                Text(isBitPerfect ? "Bit-Perfect" : "Not bit-perfect")
                    .fontWeight(.semibold)
                    .foregroundStyle(isBitPerfect ? theme.good : theme.warning)
            }
            .font(.system(size: 13))
            .lineLimit(1)
            .help(engine.signalPath?.summaryLines.joined(separator: "\n") ?? "")
        }
    }
}
