import AppKit
import Foundation

/// The focus sounds. "Glass" for the transport: soft sine notes a fifth apart, rising
/// when Focus starts and falling when it pauses, so the direction is the message. A
/// break beginning is a soft chime, one note that rings, which is a different word for
/// a different kind of moment: not a control, a change of state.
///
/// Focus and Pause play when the user presses them. Boundary sounds travel through the
/// notification (see `FocusNotifier`) so Do Not Disturb still silences them. Skip and
/// reset are the user's own hand and stay silent.
@MainActor
public enum FocusSounds {
    private static let key = "focus.sounds"

    public enum Cue: Hashable {
        /// Focus begins, by hand or at the end of a break.
        case focus
        /// A break begins, by hand or at the end of a focus round.
        case rest
        /// The user held the timer.
        case pause

        /// The file in the main bundle's Resources.
        var fileName: String {
            switch self {
            case .focus: "FocusStart.aiff"
            case .rest:  "BreakStart.aiff"
            case .pause: "Pause.aiff"
            }
        }

        static func starting(_ phase: FocusPhase) -> Cue {
            phase == .work ? .focus : .rest
        }
    }

    /// Off silences both the direct sounds and the notification's.
    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The file for the phase that begins, in the main bundle's Resources.
    static func fileName(starting phase: FocusPhase) -> String {
        Cue.starting(phase).fileName
    }

    private static var cache: [Cue: NSSound] = [:]

    /// Plays the sound for `phase` beginning, if sounds are on and the file is bundled.
    static func play(starting phase: FocusPhase) {
        play(.starting(phase))
    }

    static func play(_ cue: Cue) {
        guard isEnabled else { return }
        if cache[cue] == nil,
           let url = Bundle.main.url(forResource: cue.fileName, withExtension: nil),
           let sound = NSSound(contentsOf: url, byReference: true) {
            cache[cue] = sound
        }
        guard let sound = cache[cue] else { return }
        sound.stop()
        sound.play()
    }
}
