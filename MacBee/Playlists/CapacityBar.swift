import MacBeeLibrary
import SwiftUI

/// For MiniDisc mixes: how much of the disc (60:00, 74:00 or 80:00) the songs use, with an Overtime warning when
/// they don't fit and an Underfill warning when more than 7 minutes are left.
struct CapacityBar: View {
    let total: Double
    let capacity: Double
    @Environment(\.theme) private var theme

    var body: some View {
        let status = CapacityFiller.status(total: total, capacity: capacity)
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.surface)
                    Capsule()
                        .fill(color(status))
                        .frame(width: geometry.size.width * min(1, total / max(capacity, 1)))
                }
            }
            .frame(height: 8)
            HStack(spacing: 6) {
                Text("\(Self.clock(total)) of \(Self.clock(capacity))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.textPrimary)
                switch status {
                case let .overtime(over):
                    Label("Overtime: \(Self.clock(over)) too long", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                case let .underfill(left):
                    Label("Underfill: \(Self.clock(left)) unused", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                case .fits:
                    Text("\(Self.clock(capacity - total)) left")
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .font(.system(size: 11, weight: .medium))
        }
    }

    private func color(_ status: CapacityFiller.Status) -> Color {
        switch status {
        case .overtime: .red
        case .underfill: .orange
        case .fits: theme.accent
        }
    }

    /// 4440 -> "74:00"
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
