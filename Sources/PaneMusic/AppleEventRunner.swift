import Foundation

/// Why an Apple Event did not produce an answer.
enum AppleEventFailure: Error, Equatable, Sendable {
    /// The target app is not running, or went away mid-call.
    case notRunning
    /// Automation access has not been granted for this app.
    case denied
    /// The app answered but has no current track.
    case noTrack
    /// The app stopped answering. Usually a beachballing player.
    case timedOut
    case other(Int)
}

/// Runs AppleScript off the main thread on a single serial queue.
///
/// Apple Events block for as long as the target app takes to answer, which for a cold or
/// busy Spotify is measured in seconds. Nothing here may ever run on the main actor, and
/// nothing may run concurrently either: `NSAppleScript` is not reentrant.
///
/// `@unchecked Sendable` is honest here. Every stored property is touched only from
/// `queue`, enforced by `dispatchPrecondition`, and `NSAppleEventDescriptor` never leaves
/// the queue because callers hand in a transform that runs there.
final class AppleEventRunner: @unchecked Sendable {
    static let shared = AppleEventRunner()

    private let queue = DispatchQueue(
        label: "com.aliteo.topnotch.music.appleevents",
        qos: .userInitiated
    )
    /// Compiling a script costs more than running it, so fixed scripts are compiled once.
    private var compiled: [String: NSAppleScript] = [:]

    private init() {}

    /// Runs `source` and maps the reply with `transform`, which executes on the private
    /// queue so no descriptor escapes.
    ///
    /// - Parameter reuse: `false` for scripts built around a value, such as a seek target,
    ///   so the compile cache cannot grow without bound.
    func run<T: Sendable>(
        _ source: String,
        reuse: Bool = true,
        transform: @escaping @Sendable (NSAppleEventDescriptor) -> T
    ) async -> Result<T, AppleEventFailure> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.execute(source, reuse: reuse, transform: transform))
            }
        }
    }

    /// Fire and forget, for transport commands where the reply carries nothing.
    @discardableResult
    func runVoid(_ source: String, reuse: Bool = true) async -> Result<Void, AppleEventFailure> {
        await run(source, reuse: reuse) { _ in () }
    }

    private func execute<T>(
        _ source: String,
        reuse: Bool,
        transform: (NSAppleEventDescriptor) -> T
    ) -> Result<T, AppleEventFailure> {
        dispatchPrecondition(condition: .onQueue(queue))

        let script: NSAppleScript
        if reuse, let cached = compiled[source] {
            script = cached
        } else if let made = NSAppleScript(source: source) {
            if reuse { compiled[source] = made }
            script = made
        } else {
            return .failure(.other(0))
        }

        var errorInfo: NSDictionary?
        let reply = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return .failure(Self.classify(errorInfo))
        }
        return .success(transform(reply))
    }

    private static func classify(_ info: NSDictionary) -> AppleEventFailure {
        let code = (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        switch code {
        case -1743, -10004: return .denied         // not authorised to send Apple Events
        case -600, -609, -10814: return .notRunning
        case -1712: return .timedOut
        case -1728, -1719: return .noTrack         // no such object, or an empty artwork list
        default: return .other(code)
        }
    }
}
