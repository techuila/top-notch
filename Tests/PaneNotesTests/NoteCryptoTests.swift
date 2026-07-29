// Unit tests for the notes crypto.
//
// `@testable` rather than a public surface: sealing, the key policies and the on-disk
// layout are all internal on purpose, and widening them just to be tested would put the
// crypto in the app's public API for no benefit.

import CryptoKit
import Foundation
import LocalAuthentication
import Security
import XCTest

@testable import PaneNotes

// MARK: - Sealing and opening

final class NoteCryptoTests: XCTestCase {

    private let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    private var context: Data {
        NoteCrypto.authenticatedContext(id: id, isPrivate: false)
    }

    func testRoundTripReturnsTheSameText() throws {
        let key = NoteCrypto.makeKey()
        let text = "Buy oat milk\nring the dentist\n\u{1F511} keys are in the drawer"
        let sealed = try NoteCrypto.seal(SecureBytes(text), with: key, context: context)
        let opened = try NoteCrypto.open(sealed, with: key, context: context)
        XCTAssertEqual(opened.revealString(), text)
    }

    func testEmptyNoteRoundTrips() throws {
        let key = NoteCrypto.makeKey()
        let sealed = try NoteCrypto.seal(SecureBytes(""), with: key, context: context)
        XCTAssertEqual(try NoteCrypto.open(sealed, with: key, context: context).revealString(), "")
    }

    func testSealedBlobCarriesNonceAndTag() throws {
        let key = NoteCrypto.makeKey()
        let text = "twelve bytes"
        let sealed = try NoteCrypto.seal(SecureBytes(text), with: key, context: context)
        // 12 byte nonce + ciphertext the length of the plaintext + 16 byte tag.
        XCTAssertEqual(sealed.count, 12 + text.utf8.count + 16)
        let box = try AES.GCM.SealedBox(combined: sealed)
        XCTAssertEqual(box.nonce.withUnsafeBytes { $0.count }, 12)
        XCTAssertEqual(box.tag.count, 16)
    }

    func testSamePlaintextSealsDifferentlyEveryTime() throws {
        let key = NoteCrypto.makeKey()
        let first = try NoteCrypto.seal(SecureBytes("same"), with: key, context: context)
        let second = try NoteCrypto.seal(SecureBytes("same"), with: key, context: context)
        XCTAssertNotEqual(first, second, "a repeated nonce would leak equality between notes")
    }

    func testWrongKeyFails() throws {
        let sealed = try NoteCrypto.seal(SecureBytes("secret"), with: NoteCrypto.makeKey(), context: context)
        let other = NoteCrypto.makeKey()
        XCTAssertThrowsError(try NoteCrypto.open(sealed, with: other, context: context)) { error in
            XCTAssertEqual(error as? NoteLockError, .authenticationFailed)
        }
    }

    func testTamperedCiphertextFails() throws {
        let key = NoteCrypto.makeKey()
        var sealed = try NoteCrypto.seal(SecureBytes("secret"), with: key, context: context)
        sealed[20] ^= 0x01
        XCTAssertThrowsError(try NoteCrypto.open(sealed, with: key, context: context)) { error in
            XCTAssertEqual(error as? NoteLockError, .authenticationFailed)
        }
    }

    func testTamperedNonceFails() throws {
        let key = NoteCrypto.makeKey()
        var sealed = try NoteCrypto.seal(SecureBytes("secret"), with: key, context: context)
        sealed[0] ^= 0xFF
        XCTAssertThrowsError(try NoteCrypto.open(sealed, with: key, context: context)) { error in
            XCTAssertEqual(error as? NoteLockError, .authenticationFailed)
        }
    }

    func testTamperedTagFails() throws {
        let key = NoteCrypto.makeKey()
        var sealed = try NoteCrypto.seal(SecureBytes("secret"), with: key, context: context)
        sealed[sealed.count - 1] ^= 0x80
        XCTAssertThrowsError(try NoteCrypto.open(sealed, with: key, context: context)) { error in
            XCTAssertEqual(error as? NoteLockError, .authenticationFailed)
        }
    }

    func testTruncatedBlobIsMalformed() throws {
        let key = NoteCrypto.makeKey()
        let sealed = try NoteCrypto.seal(SecureBytes("secret"), with: key, context: context)
        let truncated = sealed.prefix(8)
        XCTAssertThrowsError(try NoteCrypto.open(Data(truncated), with: key, context: context)) { error in
            XCTAssertEqual(error as? NoteLockError, .malformedCiphertext)
        }
    }

    func testCiphertextCannotBeMovedToAnotherNote() throws {
        let key = NoteCrypto.makeKey()
        let sealed = try NoteCrypto.seal(SecureBytes("secret"), with: key, context: context)
        let otherNote = NoteCrypto.authenticatedContext(id: UUID(), isPrivate: false)
        XCTAssertThrowsError(try NoteCrypto.open(sealed, with: key, context: otherNote)) { error in
            XCTAssertEqual(error as? NoteLockError, .authenticationFailed)
        }
    }

    func testPrivacyFlagCannotBeDowngraded() throws {
        let key = NoteCrypto.makeKey()
        let privateContext = NoteCrypto.authenticatedContext(id: id, isPrivate: true)
        let sealed = try NoteCrypto.seal(SecureBytes("secret"), with: key, context: privateContext)
        let publicContext = NoteCrypto.authenticatedContext(id: id, isPrivate: false)
        XCTAssertThrowsError(try NoteCrypto.open(sealed, with: key, context: publicContext)) { error in
            XCTAssertEqual(error as? NoteLockError, .authenticationFailed)
        }
    }
}

// MARK: - The plaintext buffer

final class SecureBytesTests: XCTestCase {

    func testZeroErasesTheBuffer() {
        let bytes = SecureBytes("hunter2")
        XCTAssertEqual(bytes.revealString(), "hunter2")
        bytes.zero()
        XCTAssertEqual(bytes.byteCount, 0)
        XCTAssertEqual(bytes.revealString(), "")
        bytes.withUnsafeData { XCTAssertTrue($0.isEmpty) }
    }

    func testRoundTripsThroughData() {
        let source = Data([0x00, 0x01, 0xFE, 0xFF])
        let bytes = SecureBytes(source)
        bytes.withUnsafeData { XCTAssertEqual($0, source) }
    }
}

// MARK: - Two keys, two policies

final class NoteKeyStoreTests: XCTestCase {

    func testEverydayAndGuardedKeysAreDistinct() throws {
        let keychain = FakeKeychain()
        let store = NoteKeyStore(service: "test.notes", backend: keychain)

        let everyday = try store.key(for: .everyday)
        let guarded = try store.key(for: .guarded)

        let everydayRaw = everyday.withUnsafeBytes { Data($0) }
        let guardedRaw = guarded.withUnsafeBytes { Data($0) }
        XCTAssertEqual(everydayRaw.count, 32)
        XCTAssertEqual(guardedRaw.count, 32)
        XCTAssertNotEqual(everydayRaw, guardedRaw)
        XCTAssertEqual(keychain.items.count, 2, "the two roles must not share one Keychain item")
        XCTAssertNotEqual(NoteKeyRole.everyday.account, NoteKeyRole.guarded.account)
    }

    func testANoteSealedWithOneKeyCannotBeOpenedWithTheOther() throws {
        let store = NoteKeyStore(service: "test.notes", backend: FakeKeychain())
        let everyday = try store.key(for: .everyday)
        let guarded = try store.key(for: .guarded)
        let id = UUID()

        let publicNote = try NoteCrypto.seal(
            SecureBytes("shopping list"),
            with: everyday,
            context: NoteCrypto.authenticatedContext(id: id, isPrivate: false)
        )
        XCTAssertThrowsError(
            try NoteCrypto.open(
                publicNote,
                with: guarded,
                context: NoteCrypto.authenticatedContext(id: id, isPrivate: false)
            )
        )

        let privateNote = try NoteCrypto.seal(
            SecureBytes("passport number"),
            with: guarded,
            context: NoteCrypto.authenticatedContext(id: id, isPrivate: true)
        )
        XCTAssertThrowsError(
            try NoteCrypto.open(
                privateNote,
                with: everyday,
                context: NoteCrypto.authenticatedContext(id: id, isPrivate: true)
            ),
            "the everyday key must never open a private note"
        )
    }

    func testTheTwoItemsGetDifferentAccessPolicies() throws {
        let keychain = FakeKeychain()
        let store = NoteKeyStore(service: "test.notes", backend: keychain)
        _ = try store.key(for: .everyday)
        _ = try store.key(for: .guarded)

        let everyday = try XCTUnwrap(keychain.attributes(account: NoteKeyRole.everyday.account))
        let guarded = try XCTUnwrap(keychain.attributes(account: NoteKeyRole.guarded.account))

        XCTAssertNil(everyday[kSecAttrAccessControl as String], "the everyday key must never prompt")
        XCTAssertEqual(
            everyday[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )

        XCTAssertNotNil(guarded[kSecAttrAccessControl as String], "the private key must be gated")
        XCTAssertNil(guarded[kSecAttrAccessible as String], "an access control replaces the plain accessibility")
        XCTAssertTrue(CFGetTypeID(guarded[kSecAttrAccessControl as String] as CFTypeRef) == SecAccessControlGetTypeID())

        for attributes in [everyday, guarded] {
            XCTAssertEqual(attributes[kSecUseDataProtectionKeychain as String] as? Bool, true)
            XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
        }
    }

    func testAMissingGuardedKeyIsNotSilentlyRecreated() {
        let store = NoteKeyStore(service: "test.notes", backend: FakeKeychain())
        XCTAssertThrowsError(try store.key(for: .guarded, context: nil, creatingIfMissing: false)) { error in
            XCTAssertEqual(error as? NoteLockError, .keyMissing)
        }
    }

    func testExistenceCheckDoesNotAskForTheKeyData() throws {
        let keychain = FakeKeychain()
        let store = NoteKeyStore(service: "test.notes", backend: keychain)
        XCTAssertFalse(store.exists(.guarded))
        _ = try store.key(for: .guarded)
        XCTAssertTrue(store.exists(.guarded))
        // One data read, from the lookup inside key(). Neither exists() call asked for
        // the bytes, which is what stops the list view triggering Touch ID.
        XCTAssertEqual(keychain.dataReads, 1)
    }

    func testTheGuardedKeyIsNotReadableWithoutAnAuthenticationContext() throws {
        let store = NoteKeyStore(service: "test.notes", backend: FakeKeychain())
        _ = try store.key(for: .guarded)
        XCTAssertThrowsError(try store.key(for: .guarded, context: nil)) { error in
            XCTAssertEqual(error as? NoteLockError, .cancelledBySystem)
        }
        let authenticated = try store.key(for: .guarded, context: LAContext(), creatingIfMissing: false)
        XCTAssertEqual(authenticated.withUnsafeBytes { Data($0) }.count, 32)
    }

    func testDeletingTheGuardedKeyLeavesTheEverydayKeyAlone() throws {
        let keychain = FakeKeychain()
        let store = NoteKeyStore(service: "test.notes", backend: keychain)
        _ = try store.key(for: .everyday)
        _ = try store.key(for: .guarded)
        try store.delete(.guarded)
        XCTAssertFalse(store.exists(.guarded))
        XCTAssertTrue(store.exists(.everyday))
    }

    func testTheSameKeyComesBackOnASecondRead() throws {
        let store = NoteKeyStore(service: "test.notes", backend: FakeKeychain())
        let first = try store.key(for: .everyday).withUnsafeBytes { Data($0) }
        let second = try store.key(for: .everyday).withUnsafeBytes { Data($0) }
        XCTAssertEqual(first, second)
    }
}

// MARK: - Nothing readable reaches the disk

final class NoteFileStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notes-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testTheFileOnDiskContainsNoPlaintext() throws {
        let store = NoteFileStore(directory: directory)
        let keys = NoteKeyStore(service: "test.notes", backend: FakeKeychain())
        let key = try keys.key(for: .everyday)
        let id = UUID()
        let canary = "PLAINTEXT-CANARY-6f2a"

        let record = NoteRecord(
            id: id,
            isPrivate: false,
            created: Date(),
            modified: Date(),
            titleHint: NoteRecord.titleHint(for: canary),
            sealed: try NoteCrypto.seal(
                SecureBytes(canary),
                with: key,
                context: NoteCrypto.authenticatedContext(id: id, isPrivate: false)
            ),
            format: NoteCrypto.formatVersion
        )
        try store.write(record)

        let url = directory.appendingPathComponent("\(id.uuidString).tnote")
        let raw = try Data(contentsOf: url)
        XCTAssertNil(raw.range(of: Data(canary.utf8)), "the note text was found in the file")
        // Base64 of the ciphertext is what a JSON encoder writes, so check the decoded
        // form too rather than trusting the encoding to hide anything.
        let decoded = try JSONDecoder().decode(NoteRecord.self, from: raw)
        XCTAssertNil(decoded.sealed.range(of: Data(canary.utf8)))
        XCTAssertEqual(decoded, record)

        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testRecordsComeBackNewestFirst() throws {
        let store = NoteFileStore(directory: directory)
        let old = makeRecord(modified: Date(timeIntervalSince1970: 1_000))
        let new = makeRecord(modified: Date(timeIntervalSince1970: 2_000))
        try store.write(old)
        try store.write(new)
        XCTAssertEqual(store.loadAll().map(\.id), [new.id, old.id])
    }

    func testDeleteRemovesTheFile() throws {
        let store = NoteFileStore(directory: directory)
        let record = makeRecord(modified: Date())
        try store.write(record)
        try store.delete(id: record.id)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testTitleHintIsCoarse() {
        XCTAssertEqual(NoteRecord.titleHint(for: ""), 0)
        XCTAssertEqual(NoteRecord.titleHint(for: "short"), 0)
        XCTAssertEqual(NoteRecord.titleHint(for: String(repeating: "a", count: 16)), 2)
        XCTAssertEqual(NoteRecord.titleHint(for: String(repeating: "a", count: 400)), 3)
        // Only the first line counts, so a long body never widens the placeholder.
        XCTAssertEqual(NoteRecord.titleHint(for: "hi\n" + String(repeating: "a", count: 400)), 0)
    }

    private func makeRecord(modified: Date) -> NoteRecord {
        NoteRecord(
            id: UUID(),
            isPrivate: false,
            created: modified,
            modified: modified,
            titleHint: 0,
            sealed: Data([1, 2, 3]),
            format: NoteCrypto.formatVersion
        )
    }
}

// MARK: - Fake Keychain

/// Enough of SecItem to exercise the key store's logic. Records exactly what was asked
/// for, so the tests can assert on the access policies rather than trusting the code.
final class FakeKeychain: KeychainBackend {
    private(set) var items: [String: [String: Any]] = [:]
    private(set) var dataReads = 0

    func attributes(account: String) -> [String: Any]? { items[account] }

    func add(_ attributes: [String: Any]) -> OSStatus {
        guard let account = attributes[kSecAttrAccount as String] as? String else { return errSecParam }
        guard items[account] == nil else { return errSecDuplicateItem }
        items[account] = attributes
        return errSecSuccess
    }

    func copy(_ query: [String: Any], result: inout CFTypeRef?) -> OSStatus {
        guard let account = query[kSecAttrAccount as String] as? String else { return errSecParam }
        let wantsData = query[kSecReturnData as String] as? Bool == true
        if wantsData { dataReads += 1 }
        guard let item = items[account] else { return errSecItemNotFound }

        if wantsData {
            // A gated item never hands over its bytes without an authentication context.
            if item[kSecAttrAccessControl as String] != nil,
               query[kSecUseAuthenticationContext as String] == nil {
                return errSecInteractionNotAllowed
            }
            result = item[kSecValueData as String] as CFTypeRef?
            return errSecSuccess
        }
        result = item as CFDictionary
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        guard let account = query[kSecAttrAccount as String] as? String else { return errSecParam }
        guard items.removeValue(forKey: account) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }
}
