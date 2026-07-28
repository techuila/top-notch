import Foundation

/// Every way reading or writing a note can fail.
///
/// Each case carries its own sentence. There is no generic fallback message, because a
/// vague failure on a locked note reads as "the app is broken" when the honest answer is
/// usually "Touch ID is locked out" or "this key no longer exists". Nothing in here ever
/// results in a note being shown: a failure keeps the note locked, always.
enum NoteLockError: Error, Equatable {

    // Biometrics
    /// No Touch ID sensor on this Mac.
    case biometryUnavailable
    /// Sensor present, no fingerprints enrolled.
    case biometryNotEnrolled
    /// Too many failed attempts; the sensor is disabled until the Mac is unlocked by password.
    case biometryLockedOut
    /// The user dismissed the prompt.
    case cancelledByUser
    /// The finger on the sensor was not one of the enrolled ones.
    case biometryNoMatch
    /// macOS took the prompt away: screen lock, app switch, another auth in front of ours.
    case cancelledBySystem
    /// LocalAuthentication failed in a way that is not one of the above.
    case authenticationUnavailable(String)

    // Keys
    /// The Keychain item is gone. A Touch ID enrolment change invalidates it by design,
    /// and a migrated or restored Mac never had it.
    case keyMissing
    /// The process is not entitled to the data-protection Keychain, which means the build
    /// is not signed with `keychain-access-groups`.
    case keychainNotEntitled
    /// Anything else SecItem told us.
    case keychain(OSStatus)

    // Data
    case malformedCiphertext
    case authenticationFailed
    case encryptionFailed
    case notText
    case storage(String)

    /// One line, addressed to the user, that says what happened and what to do about it.
    var message: String {
        switch self {
        case .biometryUnavailable:
            "This Mac has no Touch ID, so private notes cannot be opened here."
        case .biometryNotEnrolled:
            "No fingerprints are enrolled. Add one in System Settings, Touch ID and Password."
        case .biometryLockedOut:
            "Touch ID is locked after too many failed attempts. Lock your Mac and unlock it with your password to re-enable it."
        case .cancelledByUser:
            "Cancelled. The note stays locked."
        case .biometryNoMatch:
            "Touch ID did not recognise that finger. The note stays locked."
        case .cancelledBySystem:
            "macOS dismissed the Touch ID prompt. Try again."
        case .authenticationUnavailable(let detail):
            "Touch ID is not available right now: \(detail)"
        case .keyMissing:
            "The private notes key is gone. It is erased when Touch ID enrolment changes, and it is never restored from a backup, so notes locked with it cannot be recovered."
        case .keychainNotEntitled:
            "This build cannot reach the Keychain. It needs to be signed with the keychain-access-groups entitlement."
        case .keychain(let status):
            "The Keychain refused the request (\(status))."
        case .malformedCiphertext:
            "This note's file is not in a shape this app understands."
        case .authenticationFailed:
            "This note failed its integrity check. It was encrypted with a different key or the file has been altered."
        case .encryptionFailed:
            "The note could not be encrypted, so nothing was written."
        case .notText:
            "This note decrypted to something that is not text."
        case .storage(let detail):
            "The note could not be written: \(detail)"
        }
    }

    /// True when trying again could plausibly work, which is what drives whether the
    /// error view offers a retry button.
    var isRetryable: Bool {
        switch self {
        case .cancelledByUser, .cancelledBySystem, .biometryNoMatch, .biometryLockedOut, .keychain:
            true
        default:
            false
        }
    }
}
