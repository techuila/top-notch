import AppKit

/// The live size of the drawn surface, shared between the SwiftUI tree that produces it
/// and the AppKit plumbing that has to route mouse events around it.
@MainActor
final class NotchHitBox {
    var size: CGSize = .zero

    /// The catch band for incoming file drags, in window coordinates. Only live while
    /// `dragArmed`, so it never costs the user a menu bar click.
    var dragBand: CGRect = .zero
    var dragArmed = false

    /// The surface in window coordinates: centred horizontally, flush with the top edge.
    func rect(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func accepts(_ point: CGPoint, in bounds: CGRect) -> Bool {
        if rect(in: bounds).contains(point) { return true }
        return dragArmed && dragBand.contains(point)
    }
}

/// Content view that refuses every point outside the drawn surface, so the transparent
/// margin around the panel never swallows a click meant for the menu bar or the desktop.
final class NotchHitTestView: NSView {
    private let hitBox: NotchHitBox

    init(hitBox: NotchHitBox) {
        self.hitBox = hitBox
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NotchHitTestView is not loadable from a nib")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitBox.accepts(point, in: bounds) else { return nil }
        return super.hitTest(point)
    }
}

/// Borderless, non-activating, always on top, present on every Space and over fullscreen.
final class NotchPanel: NSPanel {
    init(hitBox: NotchHitBox, size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Only a control that genuinely needs typing, such as a note field, takes key.
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        // Starts inert. The cursor monitor opens it up only while the pointer is on it.
        ignoresMouseEvents = true
        contentView = NotchHitTestView(hitBox: hitBox)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
