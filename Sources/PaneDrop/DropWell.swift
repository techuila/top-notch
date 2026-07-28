import AppKit
import Foundation
import NotchCore
import SwiftUI

/// The drag destination.
///
/// This is a real `NSView` rather than SwiftUI's `.onDrop` for two reasons. It has to be
/// live while the notch is collapsed, before any SwiftUI drop target has been laid out, and
/// it has to handle `NSFilePromiseReceiver`, which SwiftUI never surfaces. A promise is what
/// arrives when an image is dragged out of Safari or an attachment out of Mail: there is no
/// file on disk yet, only a promise to write one, and treating the pasteboard as a file URL
/// silently drops those.
///
/// SwiftUI content is hosted as a subview so the two event paths stay separate: AppKit hit
/// tests the hosting view for clicks and hovers, and for a drag it walks up the superview
/// chain to the nearest view registered for the dragged types, which is this one.
final class DropWellView: NSView {
    weak var shelf: DropShelf?

    private lazy var promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.aliteo.topnotch.drop.promises"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 4
        return queue
    }()

    /// A promise is read before a URL, because a dragged item can offer both and the
    /// promise is the one that produces a file when there is not one on disk yet.
    static let readableClasses: [AnyClass] = [NSFilePromiseReceiver.self, NSURL.self]
    static let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var types: [NSPasteboard.PasteboardType] = [.fileURL]
        for promised in NSFilePromiseReceiver.readableDraggedTypes {
            types.append(NSPasteboard.PasteboardType(promised))
        }
        registerForDraggedTypes(types)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        for child in subviews { child.frame = bounds }
    }

    // MARK: Destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        shelf?.beginTargeting()
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        shelf?.endTargeting()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        shelf?.endTargeting()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        accepts(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let shelf else { return false }
        shelf.endTargeting()

        return take(sender.draggingPasteboard, into: shelf)
    }

    /// Split out from `performDragOperation` so the drop can be exercised without
    /// fabricating an `NSDraggingInfo`.
    @discardableResult
    func take(_ pasteboard: NSPasteboard, into shelf: DropShelf) -> Bool {
        let objects = pasteboard.readObjects(
            forClasses: Self.readableClasses,
            options: Self.readingOptions
        ) ?? []

        var urls: [URL] = []
        var receivers: [NSFilePromiseReceiver] = []
        for object in objects {
            switch object {
            case let receiver as NSFilePromiseReceiver: receivers.append(receiver)
            case let url as NSURL: urls.append(url as URL)
            default: break
            }
        }

        shelf.ingest(urls: urls)
        for receiver in receivers { receive(receiver, into: shelf) }
        return !urls.isEmpty || !receivers.isEmpty
    }

    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        accepts(sender.draggingPasteboard)
    }

    func accepts(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(
            forClasses: Self.readableClasses,
            options: Self.readingOptions
        )
    }

    /// The promise is written into its own staging directory inside the scratch root, then
    /// adopted. Writing straight into an item directory is not possible: the promised
    /// filename is only known once the source app has produced it.
    func receive(_ receiver: NSFilePromiseReceiver, into shelf: DropShelf) {
        guard let staging = shelf.makeStagingDirectory() else { return }
        receiver.receivePromisedFiles(
            atDestination: staging,
            options: [:],
            operationQueue: promiseQueue
        ) { url, error in
            guard error == nil else { return }
            Task { @MainActor in shelf.adoptPromisedFile(at: url) }
        }
    }
}

/// Wraps SwiftUI content in a live drag destination.
///
/// Give it a frame: it fills whatever it is proposed rather than sizing to its content, so
/// the same view works as the pane background and as an invisible catcher across the top of
/// the screen while the notch is closed.
struct DropWell<Content: View>: NSViewRepresentable {
    let shelf: DropShelf
    var fallbackSize: CGSize
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> DropWellView {
        let view = DropWellView()
        view.shelf = shelf

        let host = NSHostingView(rootView: AnyView(content))
        // Without this the hosting view publishes an intrinsic size and fights the frame
        // the shell hands us.
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = view.bounds
        view.addSubview(host)

        context.coordinator.host = host
        return view
    }

    func updateNSView(_ view: DropWellView, context: Context) {
        view.shelf = shelf
        context.coordinator.host?.rootView = AnyView(content)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DropWellView, context: Context) -> CGSize? {
        var size = proposal.replacingUnspecifiedDimensions(by: fallbackSize)
        if !size.width.isFinite { size.width = fallbackSize.width }
        if !size.height.isFinite { size.height = fallbackSize.height }
        return size
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var host: NSHostingView<AnyView>?
    }
}

/// Drags the whole shelf out as one multi file drag.
///
/// SwiftUI's `.onDrag` can vend exactly one item provider, so taking everything at once
/// means an AppKit dragging session with one `NSDraggingItem` per file. Each item carries
/// its own thumbnail, which is what makes the drag read as a stack of real files.
final class ShelfDragSourceView: NSView, NSDraggingSource {
    var payload: () -> [(url: URL, image: NSImage?)] = { [] }
    var onHover: ((Bool) -> Void)?

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func layout() {
        super.layout()
        for child in subviews { child.frame = bounds }
    }

    /// The panel does not activate on click, so first mouse has to be accepted or the
    /// first drag after focusing another app would be swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The hosted SwiftUI content draws the handle but must not receive the mouse: the
    /// drag has to start here.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let files = payload()
        guard !files.isEmpty else { return }

        let origin = convert(event.locationInWindow, from: nil)
        let side = ShelfDragSourceView.dragImageSide
        var items: [NSDraggingItem] = []

        for (index, file) in files.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: file.url as NSURL)
            let offset = CGFloat(index) * 4
            item.setDraggingFrame(
                CGRect(
                    x: origin.x - side / 2 + offset,
                    y: origin.y - side / 2 - offset,
                    width: side,
                    height: side
                ),
                contents: file.image
            )
            items.append(item)
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    static let dragImageSide: CGFloat = 40
}

/// A SwiftUI handle that starts the whole shelf drag.
struct ShelfDragSource<Content: View>: NSViewRepresentable {
    var payload: () -> [(url: URL, image: NSImage?)]
    var onHover: (Bool) -> Void
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> ShelfDragSourceView {
        let view = ShelfDragSourceView()
        let host = NSHostingView(rootView: AnyView(content))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = view.bounds
        view.addSubview(host)
        context.coordinator.host = host
        apply(to: view)
        return view
    }

    func updateNSView(_ view: ShelfDragSourceView, context: Context) {
        context.coordinator.host?.rootView = AnyView(content)
        apply(to: view)
    }

    /// The hosted content draws the handle, but the `NSView` must stay the mouse target or
    /// the hosting view would swallow the drag before it started.
    private func apply(to view: ShelfDragSourceView) {
        view.payload = payload
        view.onHover = onHover
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var host: NSHostingView<AnyView>?
    }
}
