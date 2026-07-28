import CoreGraphics
import QuartzCore

/// Numbers the shell needs that `Metrics` does not define.
///
/// These are all window-plumbing or expanded-chrome values rather than design tokens the
/// panes share, which is why they live here. Every one of them is reported as a NotchCore
/// gap; if a token appears upstream the local copy goes away.
enum ShellMetrics {
    /// Slack around the panel so the expanded shadow is not clipped by the window edge.
    static let windowMargin: CGFloat = 80

    /// Headroom above the tallest pane so a pane can grow without resizing the window.
    static let heightHeadroom: CGFloat = 120

    /// Where the album art lands once the panel is open.
    static let expandedArtwork: CGFloat = 56

    /// Where the waveform lands once the panel is open.
    static let expandedWaveWidth: CGFloat = 64
    static let expandedWaveHeight: CGFloat = 22

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

    /// How far past the collapsed notch the invisible drag catcher reaches, so a drag
    /// aimed at the top of the screen is caught before the cursor is on the housing.
    static let dragCatchMargin: CGFloat = 90

    /// Extra reach for arming the catcher, so it is live before the drag arrives.
    static let dragApproach: CGFloat = 70
}
