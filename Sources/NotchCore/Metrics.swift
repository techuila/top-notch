import AppKit
import SwiftUI

/// Every size and inset in the app. Panes must not invent their own spacing.
public enum Metrics {

    // MARK: Idle

    /// Height of the idle bar. Slightly taller than the hardware notch so content
    /// sitting in the shoulders is not cramped against the bottom edge.
    public static let idleHeight: CGFloat = 38

    /// Extra width added per shoulder beyond the hardware notch when idle content exists.
    public static let shoulderPadding: CGFloat = 11

    /// Gap between two items inside the same shoulder.
    public static let slotSpacing: CGFloat = 8

    /// Fixed width of the rotating right slot. Items slide through it vertically,
    /// so the notch width must not jitter as values change.
    public static let rotorWidth: CGFloat = 58
    public static let rotorHeight: CGFloat = 16

    public static let artworkIdleSize: CGFloat = 24
    public static let ringIdleSize: CGFloat = 15

    /// Height of a waveform bar at rest. A paused track should read as a flat, quiet row
    /// of dashes, so this is a thickness rather than anything derived from the bar width.
    public static let waveformRestHeight: CGFloat = 2

    /// Thickness of the progress line that runs along the notch bottom edge.
    public static let idleProgressHeight: CGFloat = 2.5

    /// Horizontal inset for that line, so it stops where the bottom corners start to
    /// curve. Without it the line runs into the corner, gets cut by the clip, and reads
    /// as a bar hanging off the notch rather than an edge following its shape.
    public static let idleProgressInset: CGFloat = idleCornerRadius * 0.75

    // MARK: Proximity

    /// Idle dimensions grow to these when the cursor is near but has not arrived.
    public static let proximityHeight: CGFloat = 44
    public static let proximityShoulderPadding: CGFloat = 14

    // MARK: Expanded

    public static let expandedWidth: CGFloat = 520
    public static let expandedCornerRadius: CGFloat = 32
    public static let idleCornerRadius: CGFloat = 17

    /// Vertical band occupied by the pill row, measured from the top of the panel.
    public static let pillRowTop: CGFloat = 40
    public static let pillRowHeight: CGFloat = 24

    /// Where the horizontally scrolling pane host begins.
    public static let paneTop: CGFloat = 76
    public static let paneBottom: CGFloat = 18
    public static let paneInset: CGFloat = 34

    /// Fallback panel height if a pane does not state a preference.
    public static let defaultPaneHeight: CGFloat = 208

    // MARK: Inside a pane
    //
    // The scale panes lay themselves out on. Before these existed every pane defined a
    // private layout enum and the four drifted apart, which is exactly what a design
    // system is for. Anything that does not fit one of these is a gap worth reporting
    // rather than a local constant.

    /// Between a label and the value it describes.
    public static let spacingTight: CGFloat = 4
    /// Between controls in a row, and between a glyph and its text.
    public static let spacingSnug: CGFloat = 8
    /// Between stacked blocks inside a pane. The default when unsure.
    public static let spacing: CGFloat = 12
    /// Between a pane's major sections, e.g. a header and the list under it.
    public static let spacingLoose: CGFloat = 18

    /// Vertical gap between rows in a list. Smaller than `spacing` because a row already
    /// carries its own internal padding from `NotchTile`.
    public static let listRowSpacing: CGFloat = 6

    /// Blur radius that hides text while leaving its shape and width readable. Used for a
    /// private note's redacted title, where the width bucket is the only thing the file
    /// discloses. One value so nothing is redacted more weakly somewhere else.
    public static let redactionBlur: CGFloat = 3.4

    /// Panel height for a given pane content height.
    public static func panelHeight(forContent height: CGFloat) -> CGFloat {
        paneTop + height + paneBottom
    }
}

/// Where the notch physically is on a given screen, and what to do on screens without one.
public struct NotchGeometry: Equatable, Sendable {
    /// Width of the hardware camera housing. Nothing may ever be drawn inside this.
    public let hardwareWidth: CGFloat
    /// Height of the hardware camera housing.
    public let hardwareHeight: CGFloat
    /// True when the display genuinely has a notch rather than a simulated one.
    public let isPhysical: Bool
    /// Full frame of the screen this describes.
    public let screenFrame: CGRect

    public init(hardwareWidth: CGFloat, hardwareHeight: CGFloat, isPhysical: Bool, screenFrame: CGRect) {
        self.hardwareWidth = hardwareWidth
        self.hardwareHeight = hardwareHeight
        self.isPhysical = isPhysical
        self.screenFrame = screenFrame
    }

    /// Standard synthetic notch for displays without one, sized to look deliberate
    /// rather than accidental.
    public static let synthetic = NotchGeometry(
        hardwareWidth: 200, hardwareHeight: 32, isPhysical: false, screenFrame: .zero
    )

    /// Reads the real notch dimensions from a screen.
    ///
    /// On a notched Mac the menu bar is split into two auxiliary areas with the
    /// housing between them, so the housing width is whatever is left over.
    public static func measure(_ screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        guard top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            return NotchGeometry(
                hardwareWidth: synthetic.hardwareWidth,
                hardwareHeight: synthetic.hardwareHeight,
                isPhysical: false,
                screenFrame: screen.frame
            )
        }
        let housing = screen.frame.width - left.width - right.width
        return NotchGeometry(
            hardwareWidth: max(housing, 0),
            hardwareHeight: top,
            isPhysical: true,
            screenFrame: screen.frame
        )
    }

    /// The screen the notch should live on: the one with a real notch, else the main screen.
    public static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
