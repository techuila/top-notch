import SwiftUI

/// The visual language. Panes style themselves through these, never with raw values.
///
/// The notch is always dark regardless of system appearance, because at idle it must
/// read as the hardware. There is no light variant by design.
public enum Style {

    // MARK: Colour

    /// Primary text and icons on the panel.
    public static let ink = Color.white
    /// Secondary text: artist names, captions, timestamps.
    public static let inkMuted = Color.white.opacity(0.56)
    /// Tertiary: uppercase labels, hairlines, inactive pills.
    public static let inkFaint = Color.white.opacity(0.45)

    /// Fill behind a resting control such as an inactive pill or a tile.
    public static let fill = Color.white.opacity(0.07)
    /// Fill behind a hovered control.
    public static let fillHover = Color.white.opacity(0.13)
    /// Fill behind the selected pill. Deliberately near-opaque so it reads as selected
    /// against glass without needing an accent colour.
    public static let fillActive = Color.white.opacity(0.92)
    /// Text on `fillActive`.
    public static let onActive = Color(white: 0.07)

    /// Divider and dashed drop-target strokes.
    public static let hairline = Color.white.opacity(0.14)
    public static let dashed = Color.white.opacity(0.26)

    /// Semantic accents. These are the only chromatic colours in the app, and each
    /// belongs to exactly one feature so colour alone identifies a signal at idle.
    public static let focusAccent = Color(red: 1.00, green: 0.62, blue: 0.29)   // pomodoro
    public static let dropAccent  = Color(red: 0.44, green: 0.78, blue: 1.00)   // drop shelf
    public static let notesAccent = Color(red: 0.72, green: 0.66, blue: 1.00)   // quick notes
    public static let danger      = Color(red: 1.00, green: 0.42, blue: 0.38)

    public static func accent(for pane: PaneID) -> Color {
        switch pane {
        case .music: ink
        case .drop:  dropAccent
        case .notes: notesAccent
        case .focus: focusAccent
        }
    }

    // MARK: Type

    /// A track name, a note title, the headline value in a pane.
    public static let title = Font.system(size: 15, weight: .semibold, design: .default)
    /// Artist, subtitle, secondary line.
    public static let subtitle = Font.system(size: 12, weight: .regular)
    /// Body copy inside notes and lists.
    public static let body = Font.system(size: 12.5, weight: .regular)
    /// Uppercase section labels. Apply `.tracking(1.2)` and `.textCase(.uppercase)`.
    public static let label = Font.system(size: 9, weight: .semibold, design: .monospaced)
    /// Anything with digits that must not jitter: timers, elapsed time, counters.
    public static let numeric = Font.system(size: 11.5, weight: .semibold, design: .rounded)
        .monospacedDigit()
    /// The large pomodoro readout.
    public static let numericLarge = Font.system(size: 19, weight: .semibold, design: .rounded)
        .monospacedDigit()

    // MARK: Shape

    public static let tileRadius: CGFloat = 10
    public static let cardRadius: CGFloat = 14
    public static let artworkRadius: CGFloat = 13
}

/// The Liquid Glass material used by the expanded panel.
///
/// At idle the panel is pure black so it reads as the camera housing. It only becomes
/// glass once expanded, and the transition between the two is part of the open animation.
public struct NotchMaterial: ViewModifier {
    public var isExpanded: Bool
    public var cornerRadius: CGFloat

    public init(isExpanded: Bool, cornerRadius: CGFloat) {
        self.isExpanded = isExpanded
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background {
                let shape = UnevenRoundedRectangle(
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: cornerRadius,
                    style: .continuous
                )
                ZStack {
                    // Black base is always present. Glass fades in over it, so the two
                    // states cross-dissolve in place instead of swapping materials.
                    shape.fill(.black)
                    shape.fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .opacity(isExpanded ? 1 : 0)
                    shape.fill(Color.white.opacity(isExpanded ? 0.04 : 0))
                }
                .overlay {
                    // Specular top edge, the tell that makes glass read as glass.
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(isExpanded ? 0.24 : 0),
                                .white.opacity(isExpanded ? 0.06 : 0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                }
                .compositingGroup()
                .shadow(
                    color: .black.opacity(isExpanded ? 0.55 : 0),
                    radius: isExpanded ? 26 : 0, y: isExpanded ? 14 : 0
                )
            }
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: cornerRadius,
                    style: .continuous
                )
            )
    }
}

public extension View {
    func notchMaterial(isExpanded: Bool, cornerRadius: CGFloat) -> some View {
        modifier(NotchMaterial(isExpanded: isExpanded, cornerRadius: cornerRadius))
    }

    /// Standard horizontal padding for pane content.
    func paneInsets() -> some View {
        padding(.horizontal, Metrics.paneInset)
    }
}
