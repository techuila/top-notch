import Foundation

/// Shuffle and repeat over Apple Events, for the system route.
///
/// Why this exists: the MediaRemote payload never carries the modes for the players
/// that matter. Captured live from the vendored adapter with Spotify playing, the
/// payload has no `shuffleMode` and no `repeatMode` key at all, and the adapter's
/// MediaRemote `shuffle`/`repeat` subcommands exit 0 while Spotify's actual state
/// stays put. Spotify simply does not implement that side of MediaRemote. So when
/// the controlling app is one we can script, state is read and set over the same
/// Apple Event route the transport fallback already uses.
///
/// Cost discipline: one read per track change, one read on notch open, one read-back
/// after our own set command. Never on a timer, never while paused or closed.
enum PlayerModes {
    struct Modes: Sendable, Equatable {
        var shuffle: Bool?
        var repeatMode: RepeatMode?

        /// Nothing readable. What an unscriptable or denied player reports.
        static let unknown = Modes()
    }

    /// Unit separator, same convention as the state script.
    private static let separator = "\u{1F}"

    /// Reads both modes in one round trip. A denial or a stopped player comes back as
    /// `.unknown`, which the UI renders by hiding the buttons rather than guessing.
    static func read(_ kind: PlayerKind) async -> Modes {
        guard kind.isRunning else { return .unknown }
        let result = await AppleEventRunner.shared.run(readScript(for: kind)) {
            $0.stringValue ?? ""
        }
        guard case .success(let payload) = result else { return .unknown }
        let fields = payload.components(separatedBy: separator)
        guard fields.count >= 2 else { return .unknown }
        return Modes(shuffle: Bool(fields[0]), repeatMode: RepeatMode(rawValue: fields[1]))
    }

    static func set(shuffle on: Bool, for kind: PlayerKind) async {
        guard kind.isRunning else { return }
        let body = switch kind {
        case .spotify: "set shuffling to \(on)"
        case .appleMusic: "set shuffle enabled to \(on)"
        }
        await AppleEventRunner.shared.runVoid(wrap(body, for: kind))
    }

    static func set(repeatMode mode: RepeatMode, for kind: PlayerKind) async {
        guard kind.isRunning else { return }
        let landing = effective(repeatMode: mode, for: kind)
        let body = switch kind {
        case .spotify: "set repeating to \(landing == .all)"
        case .appleMusic: "set song repeat to \(landing.rawValue)"
        }
        await AppleEventRunner.shared.runVoid(wrap(body, for: kind))
    }

    /// The mode a player actually lands on when asked for `mode`. Spotify has a single
    /// `repeating` bool and no repeat-one, so `.one` clamps to off and the user's cycle
    /// degrades to a plain toggle. Also what optimistic UI updates must show.
    static func effective(repeatMode mode: RepeatMode, for kind: PlayerKind) -> RepeatMode {
        kind == .spotify && mode == .one ? .off : mode
    }

    /// How long a player takes to reflect an accepted mode command in its own scripting
    /// properties. Measured on Spotify: stale at 400ms, correct at 1s. Reading earlier
    /// returns the old state, which would revert the button it just confirmed.
    static let settleDelay: Duration = .milliseconds(1200)

    private static func readScript(for kind: PlayerKind) -> String {
        let body = switch kind {
        case .spotify:
            """
            set repeatField to "off"
            if repeating then set repeatField to "all"
            return (shuffling as text) & (character id 31) & repeatField
            """
        case .appleMusic:
            """
            set repeatField to "off"
            set theRepeat to song repeat
            if theRepeat is one then set repeatField to "one"
            if theRepeat is all then set repeatField to "all"
            return (shuffle enabled as text) & (character id 31) & repeatField
            """
        }
        return wrap(body, for: kind)
    }

    private static func wrap(_ body: String, for kind: PlayerKind) -> String {
        """
        with timeout of 5 seconds
        tell application id "\(kind.bundleID)"
        \(body)
        end tell
        end timeout
        """
    }
}
