import AppKit
import Foundation
import Observation

/// A row in the list.
struct NoteItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var modified: Date
    var title: String

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
    private func load() {
        let loaded = files.loadAll()
        records = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        order = loaded.map(\.id)
        rebuildItems()
    }

    // MARK: Navigation

    func open(_ id: UUID) {
        guard let record = records[id] else { return }
        clearFailure()
        setDraft(record.text)
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
            rebuildItems()
            setDraft("")
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
            promote(id)
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

    private func promote(_ id: UUID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    private func rebuildItems() {
        items = order.compactMap { id in
            guard let record = records[id] else { return nil }
            return NoteItem(
                id: id,
                modified: record.modified,
                title: NotesStore.firstLine(of: record.text)
            )
        }
    }

    static func firstLine(of text: String) -> String {
        let line = text.prefix(while: { !$0.isNewline }).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return NoteItem.untitled }
        return line.count > 48 ? String(line.prefix(48)) + "\u{2026}" : line
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
