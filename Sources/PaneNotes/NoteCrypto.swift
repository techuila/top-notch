import CryptoKit
import Foundation

/// Sealing and unsealing of note bodies.
///
/// Deliberately pure Foundation plus CryptoKit: no Keychain, no LocalAuthentication, no
/// AppKit. That is what makes it testable on a machine with no Secure Enclave and in a
/// binary that is not signed with a keychain entitlement.
enum NoteCrypto {

    /// Bumped only if the on-disk layout changes. It is part of the authenticated data,
    /// so a record cannot be replayed into a future format that reads it differently.
    static let formatVersion = 1

    /// Authenticated-but-not-encrypted context bound to every record.
    ///
    /// Binding the note id stops a ciphertext being copied from one note file into
    /// another, and binding the privacy flag stops a private record being re-labelled
    /// public in the hope that the app will try the non-biometric key on it.
    static func authenticatedContext(id: UUID, isPrivate: Bool) -> Data {
        Data("topnotch.note.v\(formatVersion)|\(id.uuidString)|\(isPrivate ? "private" : "public")".utf8)
    }

    /// AES-GCM seal. The returned blob is CryptoKit's combined representation:
    /// 12-byte nonce, then ciphertext, then the 16-byte tag.
    static func seal(
        _ plaintext: SecureBytes,
        with key: SymmetricKey,
        context: Data
    ) throws(NoteLockError) -> Data {
        do {
            let box = try plaintext.withUnsafeData { bytes in
                try AES.GCM.seal(bytes, using: key, authenticating: context)
            }
            guard let combined = box.combined else { throw NoteLockError.encryptionFailed }
            return combined
        } catch let error as NoteLockError {
            throw error
        } catch {
            throw NoteLockError.encryptionFailed
        }
    }

    /// Opens a combined AES-GCM blob. Any tampering with the nonce, the ciphertext, the
    /// tag or the authenticated context fails the tag check and throws.
    static func open(
        _ blob: Data,
        with key: SymmetricKey,
        context: Data
    ) throws(NoteLockError) -> SecureBytes {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: blob)
        } catch {
            throw NoteLockError.malformedCiphertext
        }
        do {
            let opened = try AES.GCM.open(box, using: key, authenticating: context)
            return SecureBytes(opened)
        } catch {
            // CryptoKit does not distinguish a wrong key from a mangled tag, and neither
            // should we: both mean this key may not read this note.
            throw NoteLockError.authenticationFailed
        }
    }

    /// A fresh 256-bit key. CryptoKit zeroes a `SymmetricKey`'s backing store when the
    /// last reference goes away, so dropping the reference is the way to forget a key.
    static func makeKey() -> SymmetricKey { SymmetricKey(size: .bits256) }
}

/// A heap buffer for plaintext that we can actually erase.
///
/// Swift `String` and `Data` give no way to guarantee a wipe, and both may leave copies
/// behind when they grow. Anything decrypted therefore lands here first, and the only
/// place a plaintext `String` exists is the live text editor, which is emptied on close.
final class SecureBytes {
    private var storage: UnsafeMutableRawBufferPointer

    init(count: Int) {
        storage = .allocate(byteCount: max(count, 1), alignment: 1)
        storage.initializeMemory(as: UInt8.self, repeating: 0)
        self.byteCount = count
    }

    /// Number of meaningful bytes. The allocation is at least one byte so the base
    /// address is never nil, but an empty note still reports zero.
    private(set) var byteCount: Int

    convenience init(_ data: Data) {
        self.init(count: data.count)
        if !data.isEmpty {
            data.withUnsafeBytes { source in
                storage.baseAddress?.copyMemory(from: source.baseAddress!, byteCount: source.count)
            }
        }
    }

    convenience init(_ text: String) {
        var utf8 = Array(text.utf8)
        self.init(count: utf8.count)
        if !utf8.isEmpty {
            utf8.withUnsafeBytes { source in
                storage.baseAddress?.copyMemory(from: source.baseAddress!, byteCount: source.count)
            }
        }
        // The temporary array held plaintext too. Erase it before it is freed.
        utf8.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress { memset_s(base, buffer.count, 0, buffer.count) }
        }
        utf8.removeAll(keepingCapacity: false)
    }

    /// Hands the bytes to a body as a `Data` that does not own or copy them.
    /// The body must not let the `Data` escape.
    func withUnsafeData<R>(_ body: (Data) throws -> R) rethrows -> R {
        guard let base = storage.baseAddress else { return try body(Data()) }
        return try body(Data(bytesNoCopy: base, count: byteCount, deallocator: .none))
    }

    /// Produces a Swift `String`, which is a copy we cannot erase. Call it once, at the
    /// moment the editor needs text, and never to log or compare.
    func revealString() -> String? {
        withUnsafeData { String(data: $0, encoding: .utf8) }
    }

    /// Overwrites the buffer. `memset_s` is used because a plain `memset` on memory that
    /// is about to be freed is exactly the store the optimiser is allowed to delete.
    func zero() {
        guard let base = storage.baseAddress, storage.count > 0 else { return }
        memset_s(base, storage.count, 0, storage.count)
        byteCount = 0
    }

    deinit {
        if let base = storage.baseAddress, storage.count > 0 {
            memset_s(base, storage.count, 0, storage.count)
        }
        storage.deallocate()
    }
}
