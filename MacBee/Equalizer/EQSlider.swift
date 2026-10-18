import MacBeeAudio
import SwiftUI

/// One vertical EQ slider: dB value on top, the track with a knob, the label underneath.
/// Drag to change; double-click puts it back to 0 dB.
struct EQSlider: View {
    let value: Float
    let label: String
    var isEnabled = true
    var width: CGFloat = 30
    let onChange: (Float) -> Void

    @Environment(\.theme) private var theme
    private let range = EqualizerSettings.gainRange
    private let trackHeight: CGFloat = 170
    private let knob: CGFloat = 14

    var body: some View {
        VStack(spacing: 6) {
            Text(Self.format(value))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(value == 0 ? theme.textTertiary : theme.textPrimary)
                .frame(height: 12)
            track
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.textSecondary)
                .frame(height: 12)
        }
        .frame(width: width)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var track: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let y = position(for: value, height: height)
            let zeroY = position(for: 0, height: height)
            ZStack(alignment: .top) {
                Capsule().fill(theme.surface).frame(width: 4)
                // Fill from the 0 dB line to the knob.
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 4, height: abs(y - zeroY))
                    .offset(y: min(y, zeroY))
                Rectangle().fill(theme.textTertiary).frame(width: 10, height: 1).offset(y: zeroY)
                Circle()
                    .fill(theme.textPrimary)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .offset(y: y - knob / 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(gain(at: drag.location.y, height: height))
            })
            .onTapGesture(count: 2) { onChange(0) }
        }
        .frame(height: trackHeight)
        .help("Drag to change. Double-click to reset to 0 dB.")
    }

    private func position(for gain: Float, height: CGFloat) -> CGFloat {
        let fraction = CGFloat((range.upperBound - gain) / (range.upperBound - range.lowerBound))
        return knob / 2 + fraction * (height - knob)
    }

    private func gain(at y: CGFloat, height: CGFloat) -> Float {
        let fraction = Float(min(max((y - knob / 2) / (height - knob), 0), 1))
        return range.upperBound - fraction * (range.upperBound - range.lowerBound)
    }

    static func format(_ dB: Float) -> String {
        if dB == 0 { return "0" }
        let text = dB.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(dB)) : String(format: "%.1f", dB)
        return dB > 0 ? "+" + text : text
    }
}
