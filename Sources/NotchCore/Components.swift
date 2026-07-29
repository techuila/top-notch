import SwiftUI

/// Shared controls. Panes use these so every button in the app reacts identically.

/// An icon button with the house hover and press behaviour: it scales down on press,
/// lifts a fill on hover, and never changes size in layout.
///
/// A toggle is the same button with `isSelected`, which borrows the selected pill's
/// near-opaque fill. Panes must not fake a selected state with a tile behind a plain
/// button; the two drift apart the moment either one is touched.
public struct NotchButton: View {
    private let symbol: String
    private let size: CGFloat
    private let isSelected: Bool
    private let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    public init(
        _ symbol: String,
        size: CGFloat = 15,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.size = size
        self.isSelected = isSelected
        self.action = action
    }

    /// Selected wins over hover: a hover tint on top of the active fill reads as a
    /// half-pressed state that does not exist.
    private var foreground: Color {
        isSelected ? Style.onActive : Style.ink.opacity(hovering ? 1 : 0.86)
    }

    private var fill: Color {
        isSelected ? Style.fillActive : Style.fill.opacity(hovering ? 1 : 0)
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: size + 14, height: size + 14)
            .background(Circle().fill(fill))
            .scaleEffect(pressed ? 0.86 : 1)
            .contentShape(Circle())
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
            .onHover { hovering = $0 }
            .notchAnimation(Motion.tap, value: pressed)
            .notchAnimation(Motion.tap, value: hovering)
            .notchAnimation(Motion.tap, value: isSelected)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A rounded surface used for list rows, file chips and tiles.
public struct NotchTile<Content: View>: View {
    private let content: Content
    private var interactive: Bool

    @State private var hovering = false

    public init(interactive: Bool = true, @ViewBuilder content: () -> Content) {
        self.interactive = interactive
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Style.tileRadius, style: .continuous)
                    .fill(hovering && interactive ? Style.fillHover : Style.fill)
            )
            .onHover { hovering = interactive && $0 }
            .notchAnimation(Motion.tap, value: hovering)
    }
}

/// The uppercase label used above values and sections.
public struct NotchLabel: View {
    private let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(Style.label)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Style.inkFaint)
    }
}

/// A horizontal progress track. Used for the scrubber, and by the shell for the
/// line that runs along the notch bottom edge at idle.
public struct NotchProgress: View {
    private let value: Double
    private let height: CGFloat
    private let tint: Color
    private let prominence: Double

    /// - Parameter prominence: 1 for the scrubber inside an open panel, lower for the
    ///   hairline on the closed notch. On a pure black notch a full-strength white fill
    ///   reads as a glowing bar rather than a progress line, so the idle line is dimmed
    ///   and its unfilled track is lifted enough to be visible at all.
    public init(
        value: Double,
        height: CGFloat = 3,
        tint: Color = Style.ink,
        prominence: Double = 1
    ) {
        self.value = min(max(value, 0), 1)
        self.height = height
        self.tint = tint
        self.prominence = min(max(prominence, 0), 1)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Style.ink.opacity(0.10 + 0.10 * prominence))
                Capsule()
                    .fill(tint.opacity(0.55 + 0.45 * prominence))
                    .frame(width: geo.size.width * value)
            }
        }
        .frame(height: height)
        .notchAnimation(Motion.ambient, value: value)
    }
}

/// A progress ring. The pomodoro uses it large in its pane and small in the idle slot,
/// which is the same view at two sizes rather than two drawings.
public struct NotchRing: View {
    private let value: Double
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let tint: Color

    public init(value: Double, size: CGFloat, lineWidth: CGFloat, tint: Color = Style.focusAccent) {
        self.value = min(max(value, 0), 1)
        self.size = size
        self.lineWidth = lineWidth
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Style.ink.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .notchAnimation(Motion.ambient, value: value)
    }
}

/// Formats a duration as m:ss or h:mm:ss, without ever changing width mid-tick.
public func notchTime(_ seconds: TimeInterval) -> String {
    let total = Int(max(seconds, 0).rounded())
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}
