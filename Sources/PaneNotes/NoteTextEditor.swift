import AppKit
import NotchCore
import SwiftUI

/// The editor, and the reason it can be typed into at all.
///
/// The notch lives in an `NSPanel` created with `.nonactivatingPanel` and `.borderless`.
/// A borderless panel returns `false` from `canBecomeKey`, and a window that cannot become
/// key never gets a `keyDown`, so a `TextEditor` dropped into the panel would render, take
/// clicks, show a caret on hover, and silently ignore every keystroke.
///
/// There are exactly two ways out of that, and this file does both:
///
/// 1. **Preferred.** The shell's panel becomes key-capable, at which point the text view is
///    hosted inline and everything is ordinary AppKit. See `NotesFocus.hostWindowIsKeyCapable`.
/// 2. **Fallback, and what runs today.** The text view is moved into a transparent child
///    panel of my own, which overrides `canBecomeKey`. It is ordered above the notch panel,
///    tracks the editor's rect every layout pass so it rides the panel's height animation,
///    and draws no background of its own, so the glass behind it is the shell's. The text
///    view genuinely lives in a key window, which is what makes the caret blink, selection
///    highlight, undo, and input methods behave normally rather than being simulated.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Escape.
    var onCancel: () -> Void
    /// Command-Return.
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NoteEditorHost {
        let host = NoteEditorHost()
        host.configure(coordinator: context.coordinator)
        context.coordinator.host = host
        return host
    }

    func updateNSView(_ host: NoteEditorHost, context: Context) {
        context.coordinator.parent = self
        let view = host.textView
        // Only touch the storage when it genuinely differs, otherwise every keystroke
        // would reset the selection and break marked text mid-composition. Assigning
        // `string` deliberately does not notify the delegate, so this cannot loop back
        // into the binding during a view update.
        if view.string != text {
            view.string = text
        }
        host.syncFocus()
    }

    static func dismantleNSView(_ host: NoteEditorHost, coordinator: Coordinator) {
        host.tearDown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        weak var host: NoteEditorHost?

        init(_ parent: NoteTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

// MARK: - The text view

/// An `NSTextView` that handles the two keys the pane owns and passes on everything else.
final class NoteTextView: NSTextView {
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    /// Escape. Overridden rather than intercepted in `keyDown` so the rest of the key
    /// bindings, including input-method composition, are untouched.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Two jobs.
    ///
    /// Command-Return commits, which is this pane's own shortcut.
    ///
    /// The clipboard and undo equivalents are handled because TopNotch is an `LSUIElement`
    /// app with no menu bar, and without a menu there is nothing to turn Command-V into
    /// `paste:`. Everything else returns to `super`, so system keystrokes are never eaten.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return super.performKeyEquivalent(with: event) }

        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !flags.contains(.shift) {
            onCommit?()
            return true
        }

        guard flags.subtracting([.command, .shift]).isEmpty,
              let character = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        switch (character, flags.contains(.shift)) {
        case ("a", false): selectAll(nil)
        case ("c", false): copy(nil)
        case ("v", false): paste(nil)
        case ("x", false): cut(nil)
        case ("z", false): undoManager?.undo()
        case ("z", true):  undoManager?.redo()
        default:           return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

// MARK: - Host view

/// Owns the text view and decides which window it should live in.
final class NoteEditorHost: NSView {
    let textView = NoteTextView()
    private let scrollView = NSScrollView()
    private var keyPanel: NoteKeyPanel?
    private var activatedApp = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not loaded from a nib") }

    func configure(coordinator: NoteTextEditor.Coordinator) {
        textView.delegate = coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = Style.Hosted.body
        textView.textColor = Style.Hosted.ink
        textView.insertionPointColor = Style.Hosted.ink
        textView.textContainerInset = NSSize(width: 2, height: 4)
        // A scratchpad, and a private one. Nothing here should be sent to the spelling
        // or completion machinery, and nothing should rewrite what was typed.
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.usesFindPanel = false
        textView.onCancel = { [weak coordinator] in coordinator?.parent.onCancel() }
        textView.onCommit = { [weak coordinator] in coordinator?.parent.onCommit() }
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView
    }

    // MARK: Window plumbing

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            tearDownKeyPanel()
            return
        }
        if NotesFocus.hostWindowIsKeyCapable(window) {
            tearDownKeyPanel()
            if scrollView.superview !== self {
                scrollView.frame = bounds
                scrollView.autoresizingMask = [.width, .height]
                addSubview(scrollView)
            }
        } else {
            buildKeyPanel(over: window)
        }
        syncFocus()
    }

    override func layout() {
        super.layout()
        // Runs on every SwiftUI layout pass, so the child panel rides the panel morph
        // instead of jumping to its final position when the spring settles.
        syncKeyPanelFrame()
    }

    private func buildKeyPanel(over parent: NSWindow) {
        if keyPanel == nil {
            let panel = NoteKeyPanel(parent: parent)
            panel.contentView = scrollView
            scrollView.autoresizingMask = [.width, .height]
            parent.addChildWindow(panel, ordered: .above)
            keyPanel = panel
        }
        syncKeyPanelFrame()
        keyPanel?.orderFront(nil)
    }

    private func syncKeyPanelFrame() {
        guard let keyPanel, let window else { return }
        let inWindow = convert(bounds, to: nil)
        let onScreen = window.convertToScreen(inWindow)
        if keyPanel.frame != onScreen {
            keyPanel.setFrame(onScreen, display: false)
        }
    }

    /// Puts the caret in the text view, activating the app first because a panel cannot
    /// be key while another application owns the keyboard.
    func syncFocus() {
        guard let target = keyPanel ?? window else { return }
        guard NotesFocus.hostWindowIsKeyCapable(target) else { return }
        if !NSApp.isActive {
            NSApp.activate()
            activatedApp = true
        }
        if !target.isKeyWindow {
            target.makeKeyAndOrderFront(nil)
        }
        if target.firstResponder !== textView {
            target.makeFirstResponder(textView)
        }
    }

    func tearDown() {
        // The undo stack is a second copy of the note's text. It goes with the editor.
        textView.undoManager?.removeAllActions()
        textView.string = ""
        tearDownKeyPanel()
        if activatedApp {
            activatedApp = false
            NSApp.deactivate()
        }
    }

    private func tearDownKeyPanel() {
        guard let keyPanel else { return }
        keyPanel.parent?.removeChildWindow(keyPanel)
        keyPanel.orderOut(nil)
        keyPanel.contentView = nil
        self.keyPanel = nil
    }
}

// MARK: - The key-capable child panel

/// A transparent panel that exists only to be key.
///
/// It is a child of the notch panel, so it moves with it, closes with it and never appears
/// in the window list. It draws nothing: the material behind the text is still the shell's
/// glass, seen through this panel.
final class NoteKeyPanel: NSPanel {
    init(parent: NSWindow) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the notch panel, and only just.
        level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
        collectionBehavior = parent.collectionBehavior
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
    }

    override var canBecomeKey: Bool { true }
    /// Never main. Main would put this in the window menu and let it own the app's menu
    /// bar, and it is a text box floating under the camera.
    override var canBecomeMain: Bool { false }
}

// MARK: - Capability check

enum NotesFocus {
    /// Whether the shell's panel can take the keyboard on its own.
    ///
    /// The moment `NotchShell` gives its panel a `canBecomeKey` override this returns true
    /// and the child panel above is never built.
    @MainActor
    static func hostWindowIsKeyCapable(_ window: NSWindow) -> Bool {
        if let panel = window as? NSPanel {
            panel.becomesKeyOnlyIfNeeded = false
        }
        return window.canBecomeKey
    }
}
