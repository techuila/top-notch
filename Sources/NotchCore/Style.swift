import AppKit
import SwiftUI

/// The visual language. Panes style themselves through these, never with raw values.
///
/// The notch is always dark regardless of system appearance, because at idle it must
/// read as the hardware. There is no light variant by design.
public enum Style {

    // MARK: Colour

    /// The palette is Teenage Engineering's OP-1 / EP-133 world: warm white, one loud
    /// orange, warm greys, black. Minimalist modern-retro; orange is the only shout.

    /// Primary text and icons on the panel. Warm white, not pure white.
    public static let ink = Color(red: 0.94, green: 0.93, blue: 0.90)
    /// Secondary text: artist names, captions, timestamps.
    public static let inkMuted = ink.opacity(0.58)
    /// Tertiary: uppercase labels, hairlines, inactive pills.
    public static let inkFaint = ink.opacity(0.45)

    /// Fill behind a resting control such as an inactive pill or a tile.
    public static let fill = ink.opacity(0.07)
    /// Fill behind a hovered control.
    public static let fillHover = ink.opacity(0.13)
    /// Fill behind the selected pill. Deliberately near-opaque so it reads as selected
    /// against glass without needing an accent colour.
    public static let fillActive = ink.opacity(0.92)
    /// Text on `fillActive`.
    public static let onActive = Color(red: 0.08, green: 0.075, blue: 0.07)

    /// Divider and dashed drop-target strokes.
    public static let hairline = ink.opacity(0.14)
    public static let dashed = ink.opacity(0.26)

    /// Semantic accents. Orange is the house accent; the others are quiet warm tones so
    /// colour still identifies a signal at idle without leaving the TE palette.
    public static let focusAccent = Color(red: 1.00, green: 0.30, blue: 0.00)   // pomodoro, TE orange
    public static let dropAccent  = Color(red: 0.78, green: 0.76, blue: 0.72)   // drop shelf, warm grey
    public static let notesAccent = Color(red: 1.00, green: 0.68, blue: 0.44)   // quick notes, soft orange
    public static let danger      = Color(red: 1.00, green: 0.26, blue: 0.19)

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

    // MARK: AppKit spellings

    /// The same tokens resolved for AppKit, for a pane hosting an `NSTextView` or any
    /// other view that cannot take a SwiftUI `Font` or `Color`.
    ///
    /// These are paired with the values above by hand. Changing one means changing the
    /// other, which is the price of AppKit not speaking SwiftUI.
    @MainActor
    public enum Hosted {
        /// Pairs with `Style.body`.
        public static let body = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        /// Pairs with `Style.ink`.
        public static let ink = NSColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1)
        /// Pairs with `Style.inkMuted`.
        public static let inkMuted = ink.withAlphaComponent(0.58)
        /// Pairs with `Style.inkFaint`.
        public static let inkFaint = ink.withAlphaComponent(0.45)
    }
}

// MARK: - Appearance

/// How the expanded panel is dressed. The idle notch is always black regardless; this
/// only governs the open panel's surface.
public enum MaterialMode: String, CaseIterable, Sendable {
    case liquidGlass
    case gradient
    case solid

    public var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .gradient: "Gradient"
        case .solid: "Solid"
        }
    }
}

/// The user's appearance choice, persisted and observable. The menu writes it, the shell
/// reads it, and a change re-renders the panel live.
@MainActor
@Observable
public final class Appearance {
    public static let shared = Appearance()

    private static let key = "style.material"

    public var material: MaterialMode {
        didSet { UserDefaults.standard.set(material.rawValue, forKey: Self.key) }
    }

    private init() {
        material = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(MaterialMode.init(rawValue:)) ?? .liquidGlass
    }
}

/// The Liquid Glass material used by the expanded panel.
///
/// At idle the panel is pure black so it reads as the camera housing. It only becomes
/// glass once expanded, and the transition between the two is part of the open animation.
public struct NotchMaterial: ViewModifier {
    public var isExpanded: Bool
    public var cornerRadius: CGFloat
    /// Concave top-corner fillet radius. Zero draws the plain bottom-rounded body; a
    /// positive value paints the full silhouette, so the flares wear the same surface
    /// as the panel instead of staying black wings.
    public var flareRadius: CGFloat

    public init(isExpanded: Bool, cornerRadius: CGFloat, flareRadius: CGFloat = 0) {
        self.isExpanded = isExpanded
        self.cornerRadius = cornerRadius
        self.flareRadius = flareRadius
    }

    public func body(content: Content) -> some View {
        let mode = Appearance.shared.material
        content
            .background {
                let shape = NotchSilhouette(
                    flareRadius: flareRadius, bottomRadius: cornerRadius
                )
                ZStack {
                    // Black base. In the glass modes it thins to a scrim when expanded,
                    // because the real glass lives in the shell's behind-window backing
                    // (an in-window material cannot sample other apps); an opaque fill
                    // here would hide it. Solid keeps the base at full strength.
                    shape.fill(.black)
                        .opacity(mode == .solid || !isExpanded ? 1 : 0.30)
                    if mode == .gradient {
                        shape.fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Style.focusAccent.opacity(0.32), location: 0),
                                    .init(color: Style.focusAccent.opacity(0.10), location: 0.35),
                                    .init(color: .clear, location: 0.7),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .opacity(isExpanded ? 1 : 0)
                    }
                    if mode == .solid {
                        shape.fill(Color(red: 0.10, green: 0.095, blue: 0.09))
                            .opacity(isExpanded ? 1 : 0)
                    }
                    shape.fill(Style.ink.opacity(isExpanded ? 0.03 : 0))
                }
                .overlay {
                    // Specular top edge, the tell that makes glass read as glass. The
                    // solid mode keeps a quieter version so the panel still has an edge.
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Style.ink.opacity(isExpanded ? (mode == .solid ? 0.14 : 0.24) : 0),
                                Style.ink.opacity(isExpanded ? 0.06 : 0),
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
                NotchSilhouette(flareRadius: flareRadius, bottomRadius: cornerRadius)
            )
    }
}

public extension View {
    func notchMaterial(
        isExpanded: Bool, cornerRadius: CGFloat, flareRadius: CGFloat = 0
    ) -> some View {
        modifier(NotchMaterial(
            isExpanded: isExpanded, cornerRadius: cornerRadius, flareRadius: flareRadius
        ))
    }

    /// Standard horizontal padding for pane content.
    func paneInsets() -> some View {
        padding(.horizontal, Metrics.paneInset)
    }
}
