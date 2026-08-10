// Unit tests for the plain-text notes store.
//
// `@testable` rather than a public surface: the record layout and the store's modes are
// internal on purpose, and widening them just to be tested would put them in the app's
// public API for no benefit.

import Foundation
import XCTest

@testable import PaneNotes

// MARK: - Files on disk

final class NoteFileStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notes-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWriteThenLoadRoundTripsTheText() throws {
        let store = NoteFileStore(directory: directory)
        let text = "Buy oat milk\nring the dentist\n\u{1F511} keys are in the drawer"
        let record = makeRecord(text: text, modified: Date())
        try store.write(record)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded, [record])
        XCTAssertEqual(loaded.first?.text, text)
    }

    func testEmptyNoteRoundTrips() throws {
        let store = NoteFileStore(directory: directory)
        let record = makeRecord(text: "", modified: Date())
        try store.write(record)
        XCTAssertEqual(store.loadAll().first?.text, "")
    }

    func testRecordsComeBackNewestFirst() throws {
        let store = NoteFileStore(directory: directory)
        let old = makeRecord(text: "old", modified: Date(timeIntervalSince1970: 1_000))
        let new = makeRecord(text: "new", modified: Date(timeIntervalSince1970: 2_000))
        try store.write(old)
        try store.write(new)
        XCTAssertEqual(store.loadAll().map(\.id), [new.id, old.id])
    }

    func testDeleteRemovesTheFile() throws {
        let store = NoteFileStore(directory: directory)
        let record = makeRecord(text: "gone soon", modified: Date())
        try store.write(record)
        try store.delete(id: record.id)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testNoteFileHasOwnerOnlyPermissions() throws {
        let store = NoteFileStore(directory: directory)
        let record = makeRecord(text: "mine", modified: Date())
        try store.write(record)
        let url = directory.appendingPathComponent("\(record.id.uuidString).tnote")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    /// A note file from the old encrypted build: format 1, a `sealed` blob, no `text`.
    /// It must be skipped, never decoded into a note, and never touched on disk.
    func testStaleEncryptedFileIsSkippedAndLeftUntouched() throws {
        let store = NoteFileStore(directory: directory)
        let stale = try writeStaleEncryptedFile()

        let plain = makeRecord(text: "still works", modified: Date())
        try store.write(plain)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.map(\.id), [plain.id], "only the plain note may load")

        let after = try Data(contentsOf: stale.url)
        XCTAssertEqual(after, stale.bytes, "the unreadable file's bytes must not change")
    }

    func testGarbageFileIsSkippedWithoutCrashing() throws {
        let store = NoteFileStore(directory: directory)
        try store.prepare()
        let url = directory.appendingPathComponent("\(UUID().uuidString).tnote")
        try Data("not json at all".utf8).write(to: url)
        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testMissingDirectoryLoadsAsEmpty() {
        let store = NoteFileStore(directory: directory)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    private func makeRecord(text: String, modified: Date) -> NoteRecord {
        NoteRecord(
            id: UUID(),
            created: modified,
            modified: modified,
            text: text,
            format: NoteRecord.currentFormat
        )
    }

    /// Recreates the old on-disk shape byte for byte enough to matter: JSON with an id,
    /// dates, a privacy flag, a base64 `sealed` blob and format 1.
    fileprivate func writeStaleEncryptedFile() throws -> (url: URL, bytes: Data) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","isPrivate":true,"created":700000000,"modified":700000000,\
        "titleHint":2,"sealed":"m0PoZBRJK7WCROBrEXH9zXlLIcTdMLN6Kg5FseKA5cI=","format":1}
        """
        let url = directory.appendingPathComponent("\(id.uuidString).tnote")
        let bytes = Data(json.utf8)
        try bytes.write(to: url)
        return (url, bytes)
    }
}

// MARK: - The store

@MainActor
final class NotesStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notes-store-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(autosaveDelay: Duration = .milliseconds(700)) -> NotesStore {
        NotesStore(files: NoteFileStore(directory: directory), autosaveDelay: autosaveDelay)
    }

    func testNewNoteOpensTheEditorAndPersistsImmediately() {
        let store = makeStore()
        store.newNote()

        XCTAssertTrue(store.showsEditor)
        XCTAssertEqual(store.noteCount, 1)
        XCTAssertEqual(store.items.first?.title, NoteItem.untitled)
        XCTAssertEqual(NoteFileStore(directory: directory).loadAll().count, 1)
    }

    func testEditedTextSurvivesARelaunch() {
        let store = makeStore()
        store.newNote()
        store.draft = "Shopping\noat milk"
        store.closeEditor()

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.noteCount, 1)
        XCTAssertEqual(relaunched.items.first?.title, "Shopping")
        if let id = relaunched.items.first?.id {
            relaunched.open(id)
            XCTAssertEqual(relaunched.draft, "Shopping\noat milk")
        } else {
            XCTFail("the note did not come back")
        }
    }

    func testAutosaveFlushesOnItsOwnAfterTheDebounce() async throws {
        let store = makeStore(autosaveDelay: .milliseconds(20))
        store.newNote()
        store.draft = "typed, then hands off"
        XCTAssertTrue(store.isSaving)

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(store.isSaving)
        let onDisk = NoteFileStore(directory: directory).loadAll()
        XCTAssertEqual(onDisk.first?.text, "typed, then hands off")
    }

    func testStandDownFlushesAndClosesTheEditor() {
        let store = makeStore()
        store.newNote()
        store.draft = "half a sentence"
        store.standDown()

        XCTAssertFalse(store.showsEditor)
        XCTAssertEqual(store.mode, .list)
        XCTAssertEqual(NoteFileStore(directory: directory).loadAll().first?.text, "half a sentence")
    }

    func testDeleteNeedsConfirmationAndThenRemovesTheNote() {
        let store = makeStore()
        store.newNote()
        guard let id = store.items.first?.id else { return XCTFail("no note") }

        store.requestDelete(id)
        XCTAssertEqual(store.pendingDeleteID, id)

        store.cancelConfirmation()
        XCTAssertEqual(store.mode, .editing(id))
        XCTAssertEqual(store.noteCount, 1)

        store.requestDelete(id)
        store.confirmDelete(id)
        XCTAssertEqual(store.noteCount, 0)
        XCTAssertFalse(store.showsEditor)
        XCTAssertTrue(NoteFileStore(directory: directory).loadAll().isEmpty)
    }

    func testLastEditedNoteSortsFirst() {
        let store = makeStore()
        store.newNote()
        store.draft = "first note"
        store.closeEditor()
        store.newNote()
        store.draft = "second note"
        store.closeEditor()
        guard store.items.count == 2 else { return XCTFail("expected two notes") }

        let older = store.items[1]
        store.open(older.id)
        store.draft = "first note, edited"
        store.closeEditor()

        XCTAssertEqual(store.items.first?.title, "first note, edited")
    }

    func testStaleEncryptedNoteDoesNotAppearAndIsNotLost() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staleID = UUID()
        let json = """
        {"id":"\(staleID.uuidString)","isPrivate":false,"created":700000000,"modified":700000000,\
        "titleHint":0,"sealed":"AAECAwQFBgcICQ==","format":1}
        """
        let staleURL = directory.appendingPathComponent("\(staleID.uuidString).tnote")
        let staleBytes = Data(json.utf8)
        try staleBytes.write(to: staleURL)

        let store = makeStore()
        XCTAssertEqual(store.noteCount, 0, "an unreadable note must not appear in the list")

        store.newNote()
        store.draft = "life goes on"
        store.closeEditor()
        XCTAssertEqual(store.noteCount, 1)

        XCTAssertEqual(try Data(contentsOf: staleURL), staleBytes, "the stale file must survive untouched")
    }

    func testFirstLineDrivesTheTitle() {
        XCTAssertEqual(NotesStore.firstLine(of: ""), NoteItem.untitled)
        XCTAssertEqual(NotesStore.firstLine(of: "   \nbody"), NoteItem.untitled)
        XCTAssertEqual(NotesStore.firstLine(of: "Title\nbody"), "Title")
        XCTAssertEqual(
            NotesStore.firstLine(of: String(repeating: "a", count: 60)),
            String(repeating: "a", count: 48) + "\u{2026}"
        )
    }
}
