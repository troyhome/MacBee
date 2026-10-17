import AppKit
import SwiftUI

/// A horizontal scroll row with left and right arrows that appear while the mouse is over it,
/// so it can be scrolled with a plain mouse (no sideways wheel or trackpad swipe needed).
struct HorizontalCarousel<Content: View>: View {
    /// How far in from the row's edges the arrows sit.
    var arrowInset: CGFloat = 6
    @ViewBuilder let content: Content

    @State private var scroller = CarouselScroller()
    @State private var hovering = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .background(EnclosingScrollViewFinder { scroller.attach($0) })
        }
        .overlay(alignment: .leading) {
            if hovering && scroller.canScrollBack {
                CarouselArrow(systemImage: "chevron.left", help: "Scroll left") { scroller.page(-1) }
                    .padding(.leading, arrowInset)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .trailing) {
            if hovering && scroller.canScrollForward {
                CarouselArrow(systemImage: "chevron.right", help: "Scroll right") { scroller.page(1) }
                    .padding(.trailing, arrowInset)
                    .transition(.opacity)
            }
        }
        .onHover { isHovering in
            scroller.refresh()
            withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering }
        }
    }
}

private struct CarouselArrow: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(hovering ? theme.elevated : theme.surface).opacity(0.95))
                .overlay(Circle().stroke(theme.separator, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Drives the AppKit scroll view behind a SwiftUI horizontal ScrollView: pages it left or right
/// and reports whether there's more to see on either side.
@MainActor
@Observable
final class CarouselScroller {
    private(set) var canScrollBack = false
    private(set) var canScrollForward = false

    @ObservationIgnored private weak var scrollView: NSScrollView?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func attach(_ scrollView: NSScrollView) {
        guard scrollView !== self.scrollView else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        self.scrollView = scrollView
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        refresh()
    }

    /// Scrolls most of a visible width left (-1) or right (+1), keeping a little of the previous page in view.
    func page(_ direction: CGFloat) {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        let target = min(max(0, clip.bounds.origin.x + direction * clip.bounds.width * 0.8), maxOffset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(NSPoint(x: target, y: clip.bounds.origin.y))
        } completionHandler: {
            MainActor.assumeIsolated {
                scrollView.reflectScrolledClipView(clip)
                self.refresh()
            }
        }
    }

    func refresh() {
        guard let scrollView else { return }
        let x = scrollView.contentView.bounds.origin.x
        let back = x > 1
        let forward = x < maxOffset - 1
        if back != canScrollBack { canScrollBack = back }
        if forward != canScrollForward { canScrollForward = forward }
    }

    private var maxOffset: CGFloat {
        guard let scrollView, let document = scrollView.documentView else { return 0 }
        return max(0, document.frame.width - scrollView.contentView.bounds.width)
    }
}

/// Finds the AppKit scroll view that a SwiftUI ScrollView is built on.
private struct EnclosingScrollViewFinder: NSViewRepresentable {
    let found: @MainActor (NSScrollView) -> Void

    func makeNSView(context: Context) -> FinderView {
        let view = FinderView()
        view.found = found
        return view
    }

    func updateNSView(_ view: FinderView, context: Context) {
        view.found = found
        view.report()
    }

    final class FinderView: NSView {
        var found: (@MainActor (NSScrollView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        func report() {
            // The scroll view may not be in place yet on the first pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView else { return }
                self.found?(scrollView)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil } // never blocks clicks
    }
}
