import AppKit
import NotchCore
import SwiftUI

/// The editor, and how it takes the keyboard.
///
/// The shell keeps the notch panel key for as long as it is open, without the app ever
/// activating (a non-activating panel takes key on its own, exactly as Spotlight does).
/// All the editor has to do is become first responder, once, on the run loop turn after
/// it lands in the window.
///
/// The previous version called `NSApp.activate()` and retried focus from `updateNSView`.
/// macOS refused the activation (it is cooperative since 14), so the panel never became
/// key, and every retry ordered the window front, which scheduled another SwiftUI update,
/// which retried again, at fifteen hundred passes a second. That was the hang on the
/// first "New note".
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Buttons in the pane reach the text view through this.
    let proxy: NoteEditorProxy
    /// Escape.
    var onCancel: () -> Void
    /// Command-Return.
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NoteEditorHost {
        let host = NoteEditorHost()
        host.configure(coordinator: context.coordinator)
        context.coordinator.host = host
        proxy.textView = host.textView
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
            host.styler.restyleAll()
            host.styler.updateActive(for: view.selectedRange())
        }
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
            host?.styler.updateActive(for: view.selectedRange())
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            host?.styler.updateActive(for: view.selectedRange())
        }
    }
}

/// A handle the pane's toolbar buttons use to format whatever is selected. Plain
/// reference type: nothing observes it, it only forwards.
@MainActor
final class NoteEditorProxy {
    weak var textView: NoteTextView?

    func bold() { textView?.toggleInline("**") }
    func italic() { textView?.toggleInline("*") }
    func strikethrough() { textView?.toggleInline("~~") }
    func bulletList() { textView?.toggleList(.bullet) }
    func numberedList() { textView?.toggleList(.numbered) }
}

// MARK: - The text view

/// An `NSTextView` that speaks markdown: it continues lists on Return, wraps selections
/// in emphasis, and handles the handful of key equivalents the pane owns.
final class NoteTextView: NSTextView {
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    enum ListKind {
        case bullet, numbered
    }

    /// Escape. Overridden rather than intercepted in `keyDown` so the rest of the key
    /// bindings, including input-method composition, are untouched.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Return inside a list item carries the list on; Return on an empty item ends it.
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let paragraph = ns.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let line = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)

        guard selection.length == 0, let list = BlockParse(line: line).list else {
            super.insertNewline(sender)
            return
        }

        if list.isEmpty {
            // The item has nothing in it. A second Return means "I am done with this
            // list", so the marker goes rather than another one appearing.
            let marker = NSRange(location: paragraph.location, length: (list.prefix as NSString).length)
            insertText("", replacementRange: marker)
            return
        }

        let next: String
        if let number = list.number {
            next = list.prefix.replacingOccurrences(of: String(number), with: String(number + 1))
        } else {
            next = list.prefix
        }
        super.insertNewline(sender)
        insertText(next, replacementRange: selectedRange())
    }

    /// Wraps the selection in `token`, or unwraps it if it already is. With nothing
    /// selected it plants a pair and leaves the caret between them.
    func toggleInline(_ token: String) {
        let ns = string as NSString
        let selection = selectedRange()
        let length = (token as NSString).length

        let before = NSRange(location: selection.location - length, length: length)
        let after = NSRange(location: selection.location + selection.length, length: length)
        let wrapped = before.location >= 0
            && after.location + after.length <= ns.length
            && ns.substring(with: before) == token
            && ns.substring(with: after) == token

        if wrapped {
            let whole = NSRange(location: before.location, length: selection.length + length * 2)
            insertText(ns.substring(with: selection), replacementRange: whole)
            setSelectedRange(NSRange(location: before.location, length: selection.length))
        } else {
            insertText(token + ns.substring(with: selection) + token, replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location + length, length: selection.length))
        }
    }

    /// Puts every selected paragraph in a list of `kind`, or takes them out of it if
    /// they already are. One edit, so one undo.
    func toggleList(_ kind: ListKind) {
        let ns = string as NSString
        let selection = selectedRange()
        let paragraphs = ns.paragraphRange(for: selection)
        let block = ns.substring(with: paragraphs)
        let trailingNewline = block.hasSuffix("\n")
        let lines = block.trimmingCharacters(in: .newlines).components(separatedBy: "\n")

        let alreadyListed = lines.allSatisfy { line in
            guard let list = BlockParse(line: line).list else { return false }
            return list.isBullet == (kind == .bullet)
        }

        var rewritten: [String] = []
        for (offset, line) in lines.enumerated() {
            let existing = BlockParse(line: line).list
            let body = existing.map { String(line.dropFirst($0.prefix.count)) } ?? line
            if alreadyListed {
                rewritten.append(body)
            } else {
                rewritten.append((kind == .bullet ? "- " : "\(offset + 1). ") + body)
            }
        }

        let replacement = rewritten.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        insertText(replacement, replacementRange: paragraphs)
        setSelectedRange(NSRange(location: paragraphs.location, length: (replacement as NSString).length))
    }

    /// Command-Return commits. Command-B, I, Shift-X, Shift-7 and Shift-9 format, the
    /// same keys Apple Notes uses for bold, italic and its two list styles.
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
        case ("b", false): toggleInline("**")
        case ("i", false): toggleInline("*")
        case ("x", true):  toggleInline("~~")
        case ("7", true):  toggleList(.bullet)
        case ("9", true):  toggleList(.numbered)
        default:           return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

// MARK: - Host view

/// Owns the text stack and takes the keyboard for it.
final class NoteEditorHost: NSView {
    let textView: NoteTextView
    let styler: MarkdownStyler
    private let scrollView = NSScrollView()
    private var tookFocus = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        // An explicit TextKit 1 stack. The styler hides syntax through the layout
        // manager's glyph generation, which only TextKit 1 exposes, and building the
        // stack by hand means the view can never silently come up on TextKit 2.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        textView = NoteTextView(frame: .zero, textContainer: container)
        styler = MarkdownStyler(storage: storage, layout: layout)
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not loaded from a nib") }

    func configure(coordinator: NoteTextEditor.Coordinator) {
        textView.delegate = coordinator
        // Plain text mode: pasted rich text arrives as characters, and the only attributes
        // in the storage are the ones the styler writes.
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = Style.Hosted.body
        textView.textColor = Style.Hosted.ink
        textView.insertionPointColor = Style.Hosted.ink
        textView.textContainerInset = NSSize(width: 2, height: 4)
        // A scratchpad. Nothing here should be sent to the spelling or completion
        // machinery, and nothing should rewrite what was typed.
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
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
    }

    // MARK: Keyboard

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !tookFocus else { return }
        tookFocus = true
        // Next turn, not now: this runs inside a SwiftUI update, and making a window key
        // from inside one schedules another. Once is enough; the panel keeps key until
        // the editor goes away.
        DispatchQueue.main.async { [weak self] in self?.takeFocus() }
    }

    private func takeFocus() {
        guard let window else { return }
        // The shell has already made the panel key. This is only a safety net for a
        // host that has not, and it costs nothing when the window is key.
        if !window.isKeyWindow {
            window.makeKey()
        }
        if window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    func tearDown() {
        // The undo stack is a second copy of the note's text. It goes with the editor.
        textView.undoManager?.removeAllActions()
        textView.string = ""
        // Key stays with the panel; the shell hands the keyboard back when the notch
        // closes. Only the caret goes.
        if let window, window.firstResponder === textView {
            window.makeFirstResponder(nil)
        }
    }
}
