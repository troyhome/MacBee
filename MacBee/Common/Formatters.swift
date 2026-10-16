import Foundation

enum Format {
    /// 225 -> "3:45", 4000 -> "1:06:40"
    static func time(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 2738 -> "46 min", 4400 -> "1 hr 13 min"
    static func minutes(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        return total >= 60 ? "\(total / 60) hr \(total % 60) min" : "\(total) min"
    }

    /// 2,433,000 seconds -> "28 days 3 h"
    static func longDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        return hours >= 24 ? "\(hours / 24) days \(hours % 24) h" : minutes(seconds)
    }

    /// "Today at 9:41 PM", "Yesterday at 8:02 AM", "Oct 3 at 6:15 PM"
    static func relativeDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    /// "9:41 PM"
    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// 24, 96000 -> "24/96"; 16, 44100 -> "16/44.1"
    static func quality(bitDepth: Int?, sampleRate: Double?) -> String? {
        guard let bits = bitDepth, bits > 1, let rate = sampleRate else { return nil }
        let khz = rate / 1000
        return "\(bits)/" + (khz.rounded() == khz ? "\(Int(khz))" : String(format: "%.1f", khz))
    }
}
