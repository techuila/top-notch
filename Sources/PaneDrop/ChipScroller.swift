import AppKit
import Foundation
import SwiftUI

/// A vertical scroll view that refuses horizontal scrolling on purpose.
///
/// Horizontal scroll and swipe belong to the shell: they move between panes, and that is
/// locked. A scroll view nested inside the pane host would otherwise latch onto a sideways
/// swipe and eat it, so the user trying to see more files would get Notes instead. Rather
/// than hope SwiftUI's scroll view chains the axis it does not use, the decision is made
/// here in one place: anything more horizontal than vertical goes straight back up the
/// responder chain, untouched, and never reaches `NSScrollView`.
final class ShelfScrollView: NSScrollView {
    /// Height of the whole grid, which the pane knows exactly because the column count is
    /// fixed. Nothing has to be measured to work out whether the shelf overflows.
    var documentHeight: CGFloat = 0 {
        didSet {
            guard documentHeight != oldValue else { return }
            needsLayout = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
            nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func layout() {
        super.layout()
        guard let document = documentView else { return }
        let size = CGSize(
            width: contentView.bounds.width,
            height: max(documentHeight, contentView.bounds.height)
        )
        guard document.frame.size != size else { return }
        document.frame = CGRect(origin: .zero, size: size)
    }
}

/// Top down coordinates, so the first row sits at the top of the shelf rather than the
/// bottom, which is where an unflipped document view would put it.
final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        for child in subviews { child.frame = bounds }
    }
}

/// Hosts the chip grid in a scroll view that only ever scrolls vertically.
struct ChipScroller<Content: View>: NSViewRepresentable {
    /// The grid's full height. Anything taller than the shelf scrolls.
    var documentHeight: CGFloat
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> ShelfScrollView {
        let scroll = ShelfScrollView()
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero

        let container = FlippedContainer()
        let host = NSHostingView(rootView: AnyView(content))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        scroll.documentView = container
        scroll.documentHeight = documentHeight
        context.coordinator.host = host
        return scroll
    }

    func updateNSView(_ scroll: ShelfScrollView, context: Context) {
        context.coordinator.host?.rootView = AnyView(content)
        scroll.documentHeight = documentHeight
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var host: NSHostingView<AnyView>?
    }
}
