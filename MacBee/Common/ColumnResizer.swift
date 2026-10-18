import AppKit
import SwiftUI

/// A thin divider you can drag sideways to resize the column next to it.
/// The line is 1 point, but the area you can grab is 12 points wide and sits above both columns
/// (their scroll bars and the A–Z strip included), so it's easy to catch, like Apple Music's dividers.
/// Double-click puts the column back to its default width.
struct ColumnResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// Which column the width belongs to: the one on the left (default) or on the right.
    var resizesLeftColumn = true
    /// Width restored by a double-click.
    var defaultWidth: Double?

    @Environment(\.theme) private var theme
    @State private var startWidth: Double?
    @State private var hovering = false
    @State private var cursorPushed = false

    private static let grabWidth: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(hovering || startWidth != nil ? theme.accent.opacity(0.7) : theme.separator)
            .frame(width: hovering || startWidth != nil ? 2 : 1)
            .frame(maxHeight: .infinity)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: Self.grabWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { setHovering($0) }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startWidth ?? width
                                startWidth = start
                                let change = resizesLeftColumn ? value.translation.width : -value.translation.width
                                width = min(max(start + change, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if let defaultWidth { width = defaultWidth }
                    })
                    .help("Drag to resize")
            }
            .zIndex(10) // above the neighbouring columns, so the whole grab area works
            .onDisappear { setHovering(false) }
    }

    private func setHovering(_ inside: Bool) {
        hovering = inside
        if inside && !cursorPushed {
            NSCursor.resizeLeftRight.push()
            cursorPushed = true
        } else if !inside && cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}
