import AppKit
import Foundation
import Observation

/// A row in the list.
struct NoteItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var modified: Date
    var title: String
    /// The body after the title, syntax stripped, for the card.
    var preview: String

    static let untitled = "New note"
}

enum NotesMode: Equatable {
    case list
    case editing(UUID)
    case confirmingDelete(UUID)
}

/// Owns the notes and the editing session.
///
/// Notes are plain text on disk. The store's jobs are the list order, the editor buffer
/// and the debounced autosave, so a note is never newer in the editor than on disk for
/// more than a moment.
@MainActor
@Observable
final class NotesStore {

    // MARK: State the views read

    private(set) var items: [NoteItem] = []
    private(set) var mode: NotesMode = .list
    /// The last failure, shown inline. Cleared by the next successful action.
    private(set) var failure: NoteStoreError?
    /// True from the moment a save is queued until it has hit the disk.
    private(set) var isSaving = false
    /// The note the editor is showing, if any. Independent of `mode` so a confirmation
    /// can sit over the editor without collapsing the panel.
    private(set) var editorNoteID: UUID?
    /// Which card the editor grew out of, so it can grow back into the same one. A note
    /// opened from its card morphs from that card; a fresh note morphs from the new-note
    /// card, because that is the one the user pressed.
    private(set) var editorOrigin: String = ""
    /// The morph identity of the new-note card.
    nonisolated static let newCardOrigin = "new"

    /// The live editor buffer, for as long as the editor is open.
    var draft: String = "" {
        didSet {
            guard !isLoadingDraft, draft != oldValue else { return }
            scheduleSave()
        }
    }

    var showsEditor: Bool { editorNoteID != nil }

    var editorItem: NoteItem? {
        guard let editorNoteID else { return nil }
        return items.first { $0.id == editorNoteID }
    }

    var pendingDeleteID: UUID? {
        if case .confirmingDelete(let id) = mode { return id }
        return nil
    }

    /// Reads `items` rather than the private order so the idle badge is observed and the
    /// shell redraws the notch when a note is added or deleted.
    var noteCount: Int { items.count }

    // MARK: Dependencies

    private let files: NoteFileStore

    // MARK: Private state

    // None of this is observed: views read `items`, `mode`, `draft` and `failure`, and
    // nothing else should redraw the pane.
    @ObservationIgnored private var records: [UUID: NoteRecord] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var isLoadingDraft = false

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSave = false
    /// Read in `deinit`, which is nonisolated. Written once, in `init`, and never touched
    /// from another thread.
    @ObservationIgnored nonisolated(unsafe) private var terminationObserver: (any NSObjectProtocol)?

    /// Long enough that a fast typist causes one write per sentence, short enough that a
    /// crash costs a fragment. Every deliberate exit path flushes anyway.
    private let autosaveDelay: Duration

    init(files: NoteFileStore = NoteFileStore(), autosaveDelay: Duration = .milliseconds(700)) {
        self.files = files
        self.autosaveDelay = autosaveDelay
        load()

        // Not a timer and not a poll: one observer so quitting mid-sentence still lands.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushNow() }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    // MARK: Loading

    /// Reads every readable note once, at init. Files from the old encrypted format do
    /// not decode and are left on disk untouched; they simply do not appear in the list.
    ///
    /// The cards sit in the order the user arranged them. Anything the arrangement does
    /// not know about (a note made before arranging existed, or by an older build) goes
    /// in front, newest first, which is where a new note lands anyway.
    private func load() {
        let loaded = files.loadAll()
        records = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let arranged = files.loadOrder().filter { records[$0] != nil }
        let unarranged = loaded.map(\.id).filter { !arranged.contains($0) }
        order = unarranged + arranged
        rebuildItems()
    }

    // MARK: Arrangement

    /// Puts `id` at `index` among the cards. The arrangement is the user's, so it is
    /// written straight away and editing a note never moves it again.
    func move(_ id: UUID, to index: Int) {
        guard let from = order.firstIndex(of: id) else { return }
        let target = min(max(index, 0), order.count - 1)
        guard from != target else { return }
        order.remove(at: from)
        order.insert(id, at: target)
        rebuildItems()
        saveOrder()
    }

    private func saveOrder() {
        do {
            try files.writeOrder(order)
        } catch {
            report(error)
        }
    }

    // MARK: Navigation

    func open(_ id: UUID) {
        guard let record = records[id] else { return }
        clearFailure()
        setDraft(record.text)
        editorOrigin = id.uuidString
        editorNoteID = id
        mode = .editing(id)
    }

    func newNote() {
        clearFailure()
        let id = UUID()
        let now = Date()
        let record = NoteRecord(
            id: id,
            created: now,
            modified: now,
            text: "",
            format: NoteRecord.currentFormat
        )
        do {
            try files.write(record)
            records[id] = record
            order.insert(id, at: 0)
            saveOrder()
            rebuildItems()
            setDraft("")
            editorOrigin = Self.newCardOrigin
            editorNoteID = id
            mode = .editing(id)
        } catch {
            report(error)
        }
    }

    func closeEditor() {
        flushNow()
        setDraft("")
        editorNoteID = nil
        mode = .list
    }

    /// Called by the pane when it scrolls away or the notch closes. Saves first, then
    /// puts everything away.
    func standDown() {
        flushNow()
        setDraft("")
        editorNoteID = nil
        mode = .list
        clearFailure()
    }

    /// Replaces the buffer without arming the autosave, for when the buffer is filled
    /// from disk rather than by the user.
    private func setDraft(_ text: String) {
        saveTask?.cancel()
        saveTask = nil
        pendingSave = false
        isLoadingDraft = true
        draft = text
        isLoadingDraft = false
    }

    // MARK: Saving

    private func scheduleSave() {
        guard editorNoteID != nil else { return }
        pendingSave = true
        isSaving = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self.flushNow()
        }
    }

    /// Writes the buffer synchronously. Called by the debounce, by every exit path and by
    /// termination, so there is no window where a note exists only in the editor.
    func flushNow() {
        saveTask?.cancel()
        saveTask = nil
        guard pendingSave, let id = editorNoteID, var record = records[id] else {
            isSaving = false
            return
        }
        pendingSave = false
        record.text = draft
        record.modified = Date()
        do {
            try files.write(record)
            records[id] = record
            rebuildItems()
            clearFailure()
        } catch {
            // Keep the buffer and stay dirty so the next flush tries again.
            pendingSave = true
            report(error)
        }
        isSaving = false
    }

    // MARK: Deletion

    func requestDelete(_ id: UUID) {
        mode = .confirmingDelete(id)
    }

    func cancelConfirmation() {
        mode = editorNoteID.map { NotesMode.editing($0) } ?? .list
    }

    func confirmDelete(_ id: UUID) {
        do {
            try files.delete(id: id)
            records[id] = nil
            order.removeAll { $0 == id }
            saveOrder()
            if editorNoteID == id {
                setDraft("")
                editorNoteID = nil
            }
            rebuildItems()
            mode = .list
            clearFailure()
        } catch {
            report(error)
        }
    }

    // MARK: Items

    private func rebuildItems() {
        items = order.compactMap { id in
            guard let record = records[id] else { return nil }
            return NoteItem(
                id: id,
                modified: record.modified,
                title: NotesStore.firstLine(of: record.text),
                preview: NotesStore.preview(of: record.text)
            )
        }
    }

    /// The first line, without its markdown, as the title.
    static func firstLine(of text: String) -> String {
        let raw = String(text.prefix(while: { !$0.isNewline }))
        let line = BlockParse.plainText(of: raw).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return NoteItem.untitled }
        return line.count > 48 ? String(line.prefix(48)) + "\u{2026}" : line
    }

    /// Everything after the first line, flattened to one run of plain words. Enough for
    /// two lines on a card; the card clips the rest.
    static func preview(of text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).dropFirst()
        let words = lines
            .map { BlockParse.plainText(of: String($0)) }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
        return words.prefix(40).joined(separator: " ")
    }

    // MARK: Failure plumbing

    private func report(_ error: any Error) {
        failure = (error as? NoteStoreError) ?? .storage(error.localizedDescription)
    }

    private func clearFailure() {
        failure = nil
    }

    /// Dismisses the inline error without changing anything else.
    func dismissFailure() { clearFailure() }
}
