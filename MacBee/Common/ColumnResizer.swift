import AppKit
import SwiftUI

/// A thin divider you can drag sideways to resize the column next to it.
struct ColumnResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// Which column the width belongs to: the one on the left (default) or on the right.
    var resizesLeftColumn = true

    @Environment(\.theme) private var theme
    @State private var startWidth: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || startWidth != nil ? theme.accent.opacity(0.6) : theme.separator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 3) // easier to grab than a 1-point line
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        startWidth = start
                        let change = resizesLeftColumn ? value.translation.width : -value.translation.width
                        width = min(max(start + change, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .padding(.horizontal, -3)
            .help("Drag to resize")
    }
}
