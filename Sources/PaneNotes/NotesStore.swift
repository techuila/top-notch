import AppKit
import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// A row in the list. Never carries a private note's text or title.
struct NoteItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var isPrivate: Bool
    var modified: Date
    var titleHint: Int
    /// `nil` means hidden on purpose: a private note that is not unlocked right now.
    var title: String?

    static let untitled = "New note"
}

enum NotesMode: Equatable {
    case list
    /// Touch ID prompt in flight for this note.
    case unlocking(UUID)
    case editing(UUID)
    case confirming(NotesConfirmation)
}

enum NotesConfirmation: Equatable {
    case lock(UUID)
    case unlock(UUID)
    case delete(UUID)
    /// The guarded key is gone, so every private note is already unreadable.
    case resetPrivateNotes
}

/// Owns the notes, the keys and the editing session.
///
/// Rules this type exists to keep:
/// - nothing reaches the disk that is not already sealed
/// - a private note's plaintext exists only between an unlock and the next relock
/// - a relock is never a UI state change alone: the key reference and the buffer go too
@MainActor
@Observable
final class NotesStore {

    // MARK: State the views read

    private(set) var items: [NoteItem] = []
    private(set) var mode: NotesMode = .list
    /// The last failure, shown inline. Cleared by the next successful action.
    private(set) var failure: NoteLockError?
    /// Which note the failure is about, so the retry button knows what to retry.
    private(set) var failedNoteID: UUID?
    /// True from the moment a save is queued until it has hit the disk.
    private(set) var isSaving = false
    /// The note the editor is showing, if any. Independent of `mode` so a confirmation
    /// can sit over the editor without collapsing the panel.
    private(set) var editorNoteID: UUID?

    /// The live editor buffer. Plaintext, in memory, for as long as the editor is open.
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

    var pendingConfirmation: NotesConfirmation? {
        if case .confirming(let confirmation) = mode { return confirmation }
        return nil
    }

    var unlockingNoteID: UUID? {
        if case .unlocking(let id) = mode { return id }
        return nil
    }

    /// Reads `items` rather than the private order so the idle badge is observed and the
    /// shell redraws the notch when a note is added or deleted.
    var noteCount: Int { items.count }

    // MARK: Dependencies

    private let files: NoteFileStore
    private let keys: NoteKeyStore

    // MARK: Private state

    // None of this is observed: views read `items`, `mode`, `draft` and `failure`, and
    // nothing else should redraw the pane.
    @ObservationIgnored private var records: [UUID: NoteRecord] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var titleCache: [UUID: String] = [:]
    /// Cached because reading it never prompts. Dropping it would only buy a Keychain
    /// round trip per keystroke.
    @ObservationIgnored private var everydayKey: SymmetricKey?
    /// Held only while a private note is open. Cleared on every relock, which is what
    /// makes the note actually lock again rather than only look locked.
    @ObservationIgnored private var guardedKey: SymmetricKey?
    @ObservationIgnored private var titlesResolved = false
    @ObservationIgnored private var isLoadingDraft = false

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSave = false
    @ObservationIgnored private var relockObservers: [(NotificationCenter, any NSObjectProtocol)] = []
    /// Read in `deinit`, which is nonisolated. Written once, in `init`, and never touched
    /// from another thread.
    @ObservationIgnored nonisolated(unsafe) private var terminationObserver: (any NSObjectProtocol)?

    /// Long enough that a fast typist causes one write per sentence, short enough that a
    /// crash costs a fragment. Every deliberate exit path flushes anyway.
    private let autosaveDelay: Duration = .milliseconds(700)

    init(files: NoteFileStore = NoteFileStore(), keys: NoteKeyStore = NoteKeyStore()) {
        self.files = files
        self.keys = keys
        loadMetadata()

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

    /// Reads metadata for every note without touching a key, so the idle badge has a
    /// count at launch without a Keychain round trip.
    private func loadMetadata() {
        let loaded = files.loadAll()
        records = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        order = loaded.map(\.id)
        rebuildItems()
    }

    /// Called when the pane scrolls into view. Public titles need the everyday key, so
    /// this is the first moment the Keychain is touched at all.
    func resolveTitlesIfNeeded() {
        guard !titlesResolved else { return }
        titlesResolved = true
        guard order.contains(where: { records[$0]?.isPrivate == false }) else { return }
        do {
            _ = try everydayKeyResolved()
            rebuildItems()
        } catch {
            report(error, for: nil)
        }
    }

    // MARK: Navigation

    func open(_ id: UUID) {
        guard let record = records[id] else { return }
        clearFailure()
        if record.isPrivate && guardedKey == nil {
            beginUnlock(id)
        } else {
            loadDraft(from: record)
        }
    }

    func newNote() {
        clearFailure()
        do {
            let key = try everydayKeyResolved()
            let id = UUID()
            let now = Date()
            let empty = SecureBytes("")
            defer { empty.zero() }
            let record = NoteRecord(
                id: id,
                isPrivate: false,
                created: now,
                modified: now,
                titleHint: 0,
                sealed: try NoteCrypto.seal(
                    empty,
                    with: key,
                    context: NoteCrypto.authenticatedContext(id: id, isPrivate: false)
                ),
                format: NoteCrypto.formatVersion
            )
            try files.write(record)
            records[id] = record
            order.insert(id, at: 0)
            titleCache[id] = NoteItem.untitled
            rebuildItems()
            setDraft("")
            editorNoteID = id
            mode = .editing(id)
        } catch {
            report(error, for: nil)
        }
    }

    func closeEditor() {
        flushNow()
        let wasPrivate = editorNoteIsPrivate
        setDraft("")
        editorNoteID = nil
        mode = .list
        if wasPrivate { relock() }
    }

    /// Called by the pane when it scrolls away or the notch closes. Saves first, then
    /// puts everything away.
    func standDown() {
        flushNow()
        setDraft("")
        editorNoteID = nil
        mode = .list
        clearFailure()
        relock()
    }

    // MARK: Unlocking

    private func beginUnlock(_ id: UUID) {
        mode = .unlocking(id)
        failedNoteID = id
        Task { [weak self] in
            guard let self else { return }
            do {
                // One context per unlock, invalidated the moment the key is out. Nothing
                // retains it, so the next private note prompts again.
                let context = try await NoteBiometrics.authenticate(reason: "unlock this private note")
                defer { context.invalidate() }
                let key = try self.keys.key(for: .guarded, context: context, creatingIfMissing: false)
                self.guardedKey = key
                self.startRelockWatch()
                self.rebuildItems()
                guard let record = self.records[id] else {
                    self.report(NoteLockError.storage("the note file has gone"), for: id)
                    self.mode = .list
                    return
                }
                self.loadDraft(from: record)
            } catch {
                // Never fall through to showing the note: the mode goes back to the list
                // and the key is dropped.
                self.report(error, for: id)
                self.mode = .list
                self.relock()
            }
        }
    }

    func retryUnlock() {
        guard let failedNoteID, records[failedNoteID]?.isPrivate == true else { return }
        beginUnlock(failedNoteID)
    }

    // MARK: Editing

    private func loadDraft(from record: NoteRecord) {
        do {
            let key = try key(for: record)
            let bytes = try NoteCrypto.open(
                record.sealed,
                with: key,
                context: NoteCrypto.authenticatedContext(id: record.id, isPrivate: record.isPrivate)
            )
            defer { bytes.zero() }
            guard let text = bytes.revealString() else { throw NoteLockError.notText }
            setDraft(text)
            titleCache[record.id] = NotesStore.firstLine(of: text)
            editorNoteID = record.id
            mode = .editing(record.id)
            clearFailure()
            rebuildItems()
        } catch {
            report(error, for: record.id)
            mode = .list
        }
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

    private var editorNoteIsPrivate: Bool {
        guard let editorNoteID else { return false }
        return records[editorNoteID]?.isPrivate ?? false
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
        do {
            let key = try key(for: record)
            let bytes = SecureBytes(draft)
            defer { bytes.zero() }
            record.sealed = try NoteCrypto.seal(
                bytes,
                with: key,
                context: NoteCrypto.authenticatedContext(id: id, isPrivate: record.isPrivate)
            )
            record.modified = Date()
            record.titleHint = NoteRecord.titleHint(for: draft)
            try files.write(record)
            records[id] = record
            titleCache[id] = NotesStore.firstLine(of: draft)
            promote(id)
            rebuildItems()
            clearFailure()
        } catch {
            // Keep the buffer and stay dirty so the next flush tries again.
            pendingSave = true
            report(error, for: id)
        }
        isSaving = false
    }

    // MARK: Privacy changes and deletion

    func requestPrivacyChange(_ id: UUID) {
        guard let record = records[id] else { return }
        mode = .confirming(record.isPrivate ? .unlock(id) : .lock(id))
    }

    func requestDelete(_ id: UUID) {
        mode = .confirming(.delete(id))
    }

    func requestPrivateReset() {
        mode = .confirming(.resetPrivateNotes)
    }

    func cancelConfirmation() {
        mode = editorNoteID.map { NotesMode.editing($0) } ?? .list
    }

    func confirm(_ confirmation: NotesConfirmation) {
        switch confirmation {
        case .lock(let id):      changePrivacy(of: id, to: true)
        case .unlock(let id):    changePrivacy(of: id, to: false)
        case .delete(let id):    delete(id)
        case .resetPrivateNotes: resetPrivateNotes()
        }
    }

    private func changePrivacy(of id: UUID, to isPrivate: Bool) {
        guard let record = records[id] else { return }
        let inEditor = editorNoteID == id
        mode = inEditor ? .editing(id) : .list
        Task { [weak self] in
            guard let self else { return }
            do {
                // Either direction needs the guarded key: to read a note that is private
                // now, or to seal one that is about to be. One prompt covers both.
                if record.isPrivate || isPrivate {
                    try await self.acquireGuardedKey(
                        reason: isPrivate ? "lock this note with Touch ID" : "remove Touch ID from this note",
                        createIfMissing: isPrivate
                    )
                }
                let plaintext: SecureBytes
                if inEditor {
                    plaintext = SecureBytes(self.draft)
                } else {
                    plaintext = try NoteCrypto.open(
                        record.sealed,
                        with: try self.key(for: record),
                        context: NoteCrypto.authenticatedContext(id: id, isPrivate: record.isPrivate)
                    )
                }
                defer { plaintext.zero() }

                var updated = record
                updated.isPrivate = isPrivate
                updated.modified = Date()
                updated.sealed = try NoteCrypto.seal(
                    plaintext,
                    with: try self.key(for: updated),
                    context: NoteCrypto.authenticatedContext(id: id, isPrivate: isPrivate)
                )
                try self.files.write(updated)
                self.records[id] = updated
                if let text = plaintext.revealString() {
                    self.titleCache[id] = NotesStore.firstLine(of: text)
                }
                self.clearFailure()
                // Coming back to public with nothing private open means the guarded key
                // has no reason to stay in memory.
                if !isPrivate, !self.editorNoteIsPrivate { self.relock() }
                self.rebuildItems()
            } catch {
                self.report(error, for: id)
            }
        }
    }

    private func delete(_ id: UUID) {
        do {
            try files.delete(id: id)
            records[id] = nil
            titleCache[id] = nil
            order.removeAll { $0 == id }
            if editorNoteID == id {
                setDraft("")
                editorNoteID = nil
            }
            rebuildItems()
            mode = .list
            clearFailure()
        } catch {
            report(error, for: id)
        }
    }

    /// Only offered when the guarded key is gone. Every private note is unreadable at
    /// that point, so this removes them and clears the dead Keychain item so a new
    /// private note can be made.
    private func resetPrivateNotes() {
        for id in order where records[id]?.isPrivate == true {
            try? files.delete(id: id)
            records[id] = nil
            titleCache[id] = nil
        }
        order.removeAll { records[$0] == nil }
        try? keys.delete(.guarded)
        guardedKey = nil
        stopRelockWatch()
        rebuildItems()
        clearFailure()
        mode = .list
    }

    // MARK: Keys

    private func everydayKeyResolved() throws(NoteLockError) -> SymmetricKey {
        if let everydayKey { return everydayKey }
        let key = try keys.key(for: .everyday)
        everydayKey = key
        return key
    }

    private func key(for record: NoteRecord) throws(NoteLockError) -> SymmetricKey {
        guard record.isPrivate else { return try everydayKeyResolved() }
        guard let guardedKey else { throw NoteLockError.cancelledBySystem }
        return guardedKey
    }

    private func acquireGuardedKey(reason: String, createIfMissing: Bool) async throws {
        if guardedKey != nil { return }
        let context = try await NoteBiometrics.authenticate(reason: reason)
        defer { context.invalidate() }
        guardedKey = try keys.key(for: .guarded, context: context, creatingIfMissing: createIfMissing)
        startRelockWatch()
    }

    // MARK: Relocking

    /// Everything that must put a private note away again. Registered only while one is
    /// open, so nothing is observed while the notch sits idle.
    private func startRelockWatch() {
        guard relockObservers.isEmpty else { return }
        let relock: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.relockFromEvent() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        relockObservers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: relock)),
            (workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: relock)),
            (workspace, workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: relock)),
            (NotificationCenter.default, NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: relock)),
            (distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: relock)),
        ]
    }

    private func stopRelockWatch() {
        for (center, token) in relockObservers { center.removeObserver(token) }
        relockObservers.removeAll()
    }

    private func relockFromEvent() {
        guard guardedKey != nil else { return }
        flushNow()
        if editorNoteIsPrivate {
            setDraft("")
            editorNoteID = nil
            mode = .list
        }
        relock()
    }

    /// Forgets the guarded key. `SymmetricKey` scrubs its own storage when the last
    /// reference goes away, so dropping it here is the erase.
    private func relock() {
        guardedKey = nil
        stopRelockWatch()
        for (id, record) in records where record.isPrivate { titleCache[id] = nil }
        rebuildItems()
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
                isPrivate: record.isPrivate,
                modified: record.modified,
                titleHint: record.titleHint,
                title: title(for: record)
            )
        }
    }

    /// A private note has no readable title unless it is unlocked right now. A public one
    /// is decrypted once and cached, which is the only reason the list can show anything.
    private func title(for record: NoteRecord) -> String? {
        if record.isPrivate && guardedKey == nil { return nil }
        if let cached = titleCache[record.id] { return cached }
        guard let key = try? key(for: record),
              let bytes = try? NoteCrypto.open(
                  record.sealed,
                  with: key,
                  context: NoteCrypto.authenticatedContext(id: record.id, isPrivate: record.isPrivate)
              )
        else { return nil }
        defer { bytes.zero() }
        guard let text = bytes.revealString() else { return nil }
        let title = NotesStore.firstLine(of: text)
        titleCache[record.id] = title
        return title
    }

    static func firstLine(of text: String) -> String {
        let line = text.prefix(while: { !$0.isNewline }).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return NoteItem.untitled }
        return line.count > 48 ? String(line.prefix(48)) + "\u{2026}" : line
    }

    // MARK: Failure plumbing

    private func report(_ error: any Error, for id: UUID?) {
        failure = (error as? NoteLockError) ?? .storage(error.localizedDescription)
        failedNoteID = id
    }

    private func clearFailure() {
        failure = nil
        failedNoteID = nil
    }

    /// Dismisses the inline error without changing anything else.
    func dismissFailure() { clearFailure() }
}
