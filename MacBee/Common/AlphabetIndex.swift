import MacBeeLibrary
import SwiftUI

/// The A–Z strip along the right edge of a long list. Click a letter (or drag along the strip) to jump there.
/// Letters with nothing under them are dimmed.
struct AlphabetIndex: View {
    /// Letters that have at least one item.
    let available: Set<String>
    let onSelect: (String) -> Void

    @Environment(\.theme) private var theme
    @State private var lastLetter: String?

    static let letters = ["#"] + (65...90).map { String(UnicodeScalar($0)!) }

    /// The index letter for a name: its first letter (accents removed), or "#" for numbers and symbols.
    static func letter(for name: String) -> String {
        guard let first = LibraryKeys.normalize(name).first else { return "#" }
        let upper = String(first).uppercased()
        return letters.contains(upper) && upper != "#" ? upper : "#"
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(Self.letters, id: \.self) { letter in
                    Text(letter)
                        .font(.mbLabel)
                        .foregroundStyle(available.contains(letter) ? theme.accent : theme.textTertiary.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let rowHeight = geometry.size.height / CGFloat(Self.letters.count)
                let index = min(max(Int(value.location.y / rowHeight), 0), Self.letters.count - 1)
                jump(to: Self.letters[index])
            }.onEnded { _ in lastLetter = nil })
        }
        .frame(width: 18)
        .frame(maxHeight: 520)
        .padding(.vertical, 8)
        .help("Jump to a letter")
    }

    /// Goes to the letter, or the next one after it that has items.
    private func jump(to letter: String) {
        guard letter != lastLetter else { return }
        lastLetter = letter
        guard let start = Self.letters.firstIndex(of: letter),
              let target = Self.letters[start...].first(where: available.contains) else { return }
        onSelect(target)
    }
}
