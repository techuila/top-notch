import CoreGraphics
import NotchCore
import QuartzCore

/// Numbers the shell needs that `Metrics` does not define.
///
/// These are all window-plumbing or expanded-chrome values rather than design tokens the
/// panes share, which is why they live here. Every one of them is reported as a NotchCore
/// gap; if a token appears upstream the local copy goes away.
enum ShellMetrics {
    /// The idle base, owner decision 2026-08-10: exactly the old proximity size, so the
    /// bottom-edge progress line always clears the hardware cutout instead of being
    /// swallowed by it. NotchCore gap: `Metrics.idleHeight` and `Metrics.shoulderPadding`
    /// still hold the smaller base the design has moved off.
    static let idleHeight: CGFloat = Metrics.proximityHeight
    static let idleShoulderPadding: CGFloat = Metrics.proximityShoulderPadding

    /// Proximity still acknowledges the cursor on top of the new base, with half the old
    /// idle-to-proximity step so the breathe reads smaller than it used to.
    /// NotchCore gap: belongs beside `Metrics.proximityHeight` once the base moves there.
    static let proximityHeight: CGFloat =
        Metrics.proximityHeight + (Metrics.proximityHeight - Metrics.idleHeight) / 2
    static let proximityShoulderPadding: CGFloat =
        Metrics.proximityShoulderPadding
        + (Metrics.proximityShoulderPadding - Metrics.shoulderPadding) / 2

    /// Extra gap between the hardware housing and the pill row, so the pills do not sit
    /// flush under the cutout. One loose step from the pane spacing scale; everything
    /// below the pills shifts down with it. NotchCore gap: belongs in `Metrics.pillRowTop`.
    static let pillBreathingRoom: CGFloat = Metrics.spacingLoose

    /// Where the border progress line stops short of the expanded panel's bottom corners,
    /// mirroring how `Metrics.idleProgressInset` derives from the idle corner radius.
    /// NotchCore gap: belongs beside `Metrics.idleProgressInset`.
    static let expandedProgressInset: CGFloat = Metrics.expandedCornerRadius * 0.75

    /// Lift of the bottom-edge progress line off the very edge, shared by the idle bar
    /// and the expanded border so the line lands identically in both.
    static let progressEdgeLift: CGFloat = 1

    /// Slack around the panel so the expanded shadow is not clipped by the window edge.
    static let windowMargin: CGFloat = 80

    /// Headroom above the tallest pane so a pane can grow without resizing the window.
    static let heightHeadroom: CGFloat = 120

    /// Pill row spacing and horizontal text inset.
    static let pillSpacing: CGFloat = 6
    static let pillInset: CGFloat = 12

    /// Gap between a glyph or ring and the value beside it inside one idle slot.
    static let itemSpacing: CGFloat = 5

    /// Forgiveness around the panel edge when deciding whether the cursor is on it.
    static let hitSlack: CGFloat = 2

    /// Cursor sampling ceiling. One display frame is plenty for a hover test.
    static let sampleInterval: CFTimeInterval = 1.0 / 60.0

    /// Minimum gap between two pane steps driven by a classic mouse wheel.
    static let wheelDebounce: CFTimeInterval = 0.22

    /// Width of the music pane's trailing waveform column, mirrored here so the
    /// travelling waveform's expanded anchor lands exactly on it. NotchCore gap:
    /// the pane hardcodes the same number; both belong in `Metrics`.
    static let expandedWaveWidth: CGFloat = 26

    /// Accumulated horizontal trackpad travel that commits one pane step.
    static let swipeThreshold: CGFloat = 60

    /// How far past the collapsed notch the invisible drag catcher reaches, so a drag
    /// aimed at the top of the screen is caught before the cursor is on the housing.
    static let dragCatchMargin: CGFloat = 90

    /// Extra reach for arming the catcher, so it is live before the drag arrives.
    static let dragApproach: CGFloat = 70

    /// How far the whole surface swells when a pane asks for a pulse. Small on purpose:
    /// the notch is acknowledging something, not announcing itself.
    static let pulseScale: CGFloat = 1.045
}
