import SwiftUI

/// Every animation in TopNotch comes from here. Nothing hardcodes a duration.
///
/// SwiftUI springs are used rather than bezier curves because they interrupt and
/// retarget gracefully, which matters when the user flicks in and out of the notch.
public enum Motion {

    /// The panel opening, closing, or changing height between panes.
    /// This is the signature move of the app.
    public static let morph = Animation.spring(response: 0.42, dampingFraction: 0.78)

    /// An idle slot appearing, collapsing to zero width, or handing over.
    public static let slot = Animation.spring(response: 0.34, dampingFraction: 0.82)

    /// The rotating right shoulder sliding one item up.
    public static let rotate = Animation.spring(response: 0.46, dampingFraction: 0.86)

    /// Content settling into place inside a pane after the panel has grown.
    public static let content = Animation.spring(response: 0.34, dampingFraction: 0.9)

    /// Small acknowledgements: a button press, a hover tint, a value ticking.
    public static let tap = Animation.spring(response: 0.22, dampingFraction: 0.7)

    /// Continuous, non-interactive motion such as the waveform or a progress ring.
    public static let ambient = Animation.easeInOut(duration: 0.28)

    /// How long the right shoulder holds one item before rotating.
    public static let rotationDwell: Duration = .seconds(3.4)

    /// Cursor proximity that triggers the pre-hover breath, in points from the notch.
    public static let proximityRadius: CGFloat = 120

    /// Grace period before collapsing after the cursor leaves, so a slip does not close it.
    public static let closeGrace: Duration = .milliseconds(140)

    /// How long the notch must sit closed before a pane's focus claim is applied.
    ///
    /// The wait exists so the notch never changes what it is about while somebody is
    /// looking at it. An open panel does not count down at all: the clock starts when the
    /// panel closes, and reopening it starts the wait over.
    public static let focusClaimDelay: Duration = .seconds(3)

    /// Resolves to `nil` when the user has asked for reduced motion, which makes
    /// `withAnimation(Motion.reduced(.morph))` a no-op transition.
    public static func reduced(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }
}

public extension View {
    /// Applies an animation that automatically disables itself under Reduce Motion.
    func notchAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        self.animation(Motion.reduced(animation), value: value)
    }
}
