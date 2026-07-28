import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The two keys.
///
/// Both are 256-bit symmetric keys, not a key pair. The names describe who may read them,
/// not asymmetric roles.
enum NoteKeyRole: String, CaseIterable, Sendable {
    /// Public notes. Encrypted at rest so a stolen disk or a Time Machine snapshot reveals
    /// nothing, but readable with no prompt whenever the login keychain is unlocked.
    case everyday
    /// Private notes. Held behind a `SecAccessControl` so the Secure Enclave will not
    /// release it without a live Touch ID match.
    case guarded

    var account: String {
        switch self {
        case .everyday: "notes.key.everyday.v1"
        case .guarded:  "notes.key.guarded.v1"
        }
    }

    var requiresBiometry: Bool { self == .guarded }
}

/// The SecItem calls, behind a protocol so the key store's logic can be tested without a
/// Keychain. Only `SystemKeychain` ever talks to the real one.
protocol KeychainBackend {
    func add(_ attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any], result: inout CFTypeRef?) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychain: KeychainBackend {
    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func copy(_ query: [String: Any], result: inout CFTypeRef?) -> OSStatus {
        SecItemCopyMatching(query as CFDictionary, &result)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Reads and creates the two note keys.
///
/// Every item goes into the data-protection Keychain (`kSecUseDataProtectionKeychain`),
/// which is the only one where a `SecAccessControl` is enforced by the Secure Enclave
/// rather than by a prompt the process could talk its way past.
struct NoteKeyStore {
    let service: String
    let backend: KeychainBackend

    init(service: String = "com.aliteo.topnotch.notes", backend: KeychainBackend = SystemKeychain()) {
        self.service = service
        self.backend = backend
    }

    // MARK: Reading

    /// Fetches an existing key, creating it only if it has never existed.
    ///
    /// `context` must be an already-evaluated `LAContext` for the guarded role. Passing
    /// an un-evaluated one would make SecItemCopyMatching raise its own prompt, whose
    /// failures arrive as opaque OSStatus values instead of the `LAError` cases the UI
    /// needs to tell the user apart.
    func key(
        for role: NoteKeyRole,
        context: LAContext? = nil,
        creatingIfMissing: Bool = true
    ) throws(NoteLockError) -> SymmetricKey {
        switch try read(role, context: context) {
        case .some(let key):
            return key
        case .none:
            guard creatingIfMissing else { throw NoteLockError.keyMissing }
            return try create(role)
        }
    }

    /// True when the item exists. For the guarded role this deliberately asks only for the
    /// attributes and not the data, so it answers without a Touch ID prompt.
    func exists(_ role: NoteKeyRole) -> Bool {
        var query = baseQuery(role)
        query[kSecReturnData as String] = false
        query[kSecReturnAttributes as String] = true
        if role.requiresBiometry {
            // Attributes only, and a context that refuses to put anything on screen, so
            // asking whether a private note's key exists can never raise a prompt.
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: CFTypeRef?
        let status = backend.copy(query, result: &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    func delete(_ role: NoteKeyRole) throws(NoteLockError) {
        let status = backend.delete(baseQuery(role))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mapped(status)
        }
    }

    // MARK: Internals

    private func read(_ role: NoteKeyRole, context: LAContext?) throws(NoteLockError) -> SymmetricKey? {
        var query = baseQuery(role)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: CFTypeRef?
        let status = backend.copy(query, result: &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { throw NoteLockError.keyMissing }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw mapped(status)
        }
    }

    private func create(_ role: NoteKeyRole) throws(NoteLockError) -> SymmetricKey {
        let key = NoteCrypto.makeKey()
        let raw = key.withUnsafeBytes { Data($0) }

        var attributes = baseQuery(role)
        attributes[kSecValueData as String] = raw
        if role.requiresBiometry {
            attributes[kSecAttrAccessControl as String] = try accessControl()
        } else {
            // Device-bound and never synced: a stolen disk has the ciphertext but the key
            // lives only in this Mac's keychain, and iCloud Keychain never sees it.
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = backend.add(attributes)
        guard status == errSecSuccess else { throw mapped(status) }
        return key
    }

    /// `.biometryCurrentSet` rather than `.biometryAny`: adding or removing a fingerprint
    /// invalidates the key. That is the strict reading, and it is the point. The cost is
    /// that private notes become unreadable after an enrolment change, which is why
    /// `.keyMissing` says so in plain words instead of quietly making a new key.
    ///
    /// `.userPresence` was rejected: it lets the login password stand in for the finger,
    /// and a password typed into a floating notch panel is a worse story than Touch ID.
    private func accessControl() throws(NoteLockError) -> SecAccessControl {
        var error: Unmanaged<CFError>?
        let control = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &error
        )
        guard let control else {
            let detail = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw NoteLockError.authenticationUnavailable(detail)
        }
        return control
    }

    private func baseQuery(_ role: NoteKeyRole) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: role.account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func mapped(_ status: OSStatus) -> NoteLockError {
        switch status {
        case errSecItemNotFound:            .keyMissing
        case errSecUserCanceled:            .cancelledByUser
        case errSecAuthFailed:              .biometryNoMatch
        case errSecInteractionNotAllowed:   .cancelledBySystem
        case errSecMissingEntitlement:      .keychainNotEntitled
        default:                            .keychain(status)
        }
    }
}

/// The Touch ID prompt.
///
/// A context is created for one unlock and invalidated the moment the key has been read.
/// It is never stored on the pane, never reused for a second note, and reuse is switched
/// off outright so a match cannot silently satisfy a later prompt.
enum NoteBiometrics {

    static func authenticate(reason: String) async throws(NoteLockError) -> LAContext {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.localizedCancelTitle = "Cancel"

        var probe: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &probe) else {
            context.invalidate()
            throw map(probe)
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            context.invalidate()
            throw map(error as NSError)
        }
        return context
    }

    private static func map(_ error: NSError?) -> NoteLockError {
        guard let error else { return .authenticationUnavailable("no detail given") }
        guard error.domain == LAError.errorDomain, let code = LAError.Code(rawValue: error.code) else {
            return .authenticationUnavailable(error.localizedDescription)
        }
        switch code {
        case .biometryNotAvailable:                     return .biometryUnavailable
        case .biometryNotEnrolled:                      return .biometryNotEnrolled
        case .biometryLockout:                          return .biometryLockedOut
        case .userCancel, .appCancel:                   return .cancelledByUser
        case .systemCancel, .notInteractive:            return .cancelledBySystem
        case .userFallback:                             return .cancelledByUser
        case .authenticationFailed:                     return .biometryNoMatch
        case .invalidContext:                           return .cancelledBySystem
        case .passcodeNotSet:                           return .authenticationUnavailable("this Mac has no login password set")
        default:                                        return .authenticationUnavailable(error.localizedDescription)
        }
    }
}
