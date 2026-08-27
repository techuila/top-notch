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
        // The controller makes the panel key for as long as it is open. Key is what buys
        // the cursor: a window that is not key never gets to set it, and the pointer
        // over a button would stay whatever the app behind wanted.
        becomesKeyOnlyIfNeeded = false
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

    /// Set by the controller for as long as the panel is open. When it is false the
    /// panel refuses key outright, which is what lets the relay below give the keyboard
    /// away: when a key window orders out AppKit re-keys any window of its own app that
    /// will take it, and this one must not.
    var wantsKey = false

    override var canBecomeKey: Bool { wantsKey }
    override var canBecomeMain: Bool { false }
}

/// Takes key off the notch panel for one turn, so the keyboard goes back to whichever
/// window had it before the notch opened.
///
/// A non-activating panel keeps key until another window takes it or it orders out, and
/// ordering the notch out would collapse it. This panel is zero-sized, draws nothing, and
/// exists only to be key for an instant; when it orders out the window server hands the
/// keyboard back to the frontmost app's window, exactly as it does when Spotlight closes.
final class KeyRelayPanel: NSPanel {
    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        hasShadow = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Gives the keyboard back if `panel` currently holds it.
    static func handBack(from panel: NSWindow) {
        guard panel.isKeyWindow else { return }
        panel.makeFirstResponder(nil)
        let relay = KeyRelayPanel()
        relay.makeKeyAndOrderFront(nil)
        relay.orderOut(nil)
    }
}
