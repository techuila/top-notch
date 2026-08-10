import NotchCore
import SwiftUI

/// Quick notes in the notch.
///
/// Notes are plain text: they open with no prompt and persist as ordinary files. There is
/// no lock, no Touch ID and no Keychain use anywhere in this pane.
@MainActor
@Observable
public final class NotesPane: NotchPane {
    public let id: PaneID = .notes

    /// The list. Roughly four rows before it scrolls.
    private static let listHeight: CGFloat = 142
    /// The editor. One step taller, and constant while typing so the panel does not
    /// breathe on every keystroke.
    private static let editorHeight: CGFloat = 236

    private let store: NotesStore

    public init() {
        store = NotesStore()
    }

    init(store: NotesStore) {
        self.store = store
    }

    public var contentHeight: CGFloat {
        store.showsEditor ? Self.editorHeight : Self.listHeight
    }

    /// Note *count* only. The idle bar sits on screen all day in front of whoever walks
    /// past, so nothing from inside a note is ever published here.
    public var idle: IdleSignal {
        let count = store.noteCount
        guard count > 0 else { return .inactive }
        return IdleSignal(
            isLive: true,
            priority: 30,
            pinnedLeading: nil,
            identity: .glyph(PaneID.notes.glyph),
            rotating: .badge(symbol: PaneID.notes.glyph, text: "\(count)"),
            progress: nil
        )
    }

    public func content() -> AnyView {
        AnyView(NotesPaneView(store: store))
    }

    /// Nothing to start: notes load once at init and there are no observers or timers.
    public func activate() {}

    /// The pane scrolled away or the notch closed. Save what is in the editor, then
    /// return to the list.
    public func deactivate() {
        store.standDown()
    }
}
