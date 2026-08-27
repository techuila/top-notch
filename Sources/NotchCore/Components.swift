import AppKit
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
            .notchPointer()
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
            .modifier(PointerOnHover(enabled: interactive))
            .onHover { hovering = interactive && $0 }
            .notchAnimation(Motion.tap, value: hovering)
    }
}

public extension View {
    /// The pointing hand every clickable control shows on hover. Anything that reacts to
    /// a tap wears this, so the cursor alone says what is a button and what is not.
    func notchPointer() -> some View {
        modifier(PointerOnHover(enabled: true))
    }
}

/// Every haptic in TopNotch comes from here, so the whole app speaks one touch
/// language on a Force Touch trackpad. Only things being carried are felt (owner
/// decision, 2026-08-27): a click when something is picked up, a tick when it crosses
/// into a new place, a click when it lands. Hovering and pressing are silent; a tick on
/// every button made the app feel busy under the finger. Nothing plays when the user
/// has switched it off.
@MainActor
public enum NotchHaptics {
    private static let key = "notch.haptics"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// A card coming off the grid.
    public static func lift() { perform(.levelChange) }
    /// A carried thing crossing into a new place: a card into a new slot, a file drag
    /// arriving over the notch.
    public static func snap() { perform(.alignment) }
    /// A carried thing landing: a card in its slot, files on the shelf.
    public static func drop() { perform(.generic) }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

/// One arbiter for the cursor. SwiftUI delivers the hover exits and entries caused by
/// one mouse move in no fixed order, so a control's exit can land after its neighbour's
/// entry, and "arrow on exit" would wipe the neighbour's hand. Every hovered control
/// reports in and the cursor follows the count, whichever callback ran last.
///
/// The cursor is only ours while the notch panel is the key window, which the shell
/// arranges whenever the panel is open. `pointerStyle` and cursor rects were tried and
/// are inert here: both need a key window too, and neither survives the panel's
/// hover-driven lifecycle.
@MainActor
public final class NotchPointer {
    public static let shared = NotchPointer()

    private var hands = Set<UUID>()

    private init() {}

    fileprivate func enter(_ id: UUID) {
        hands.insert(id)
        apply()
    }

    fileprivate func leave(_ id: UUID) {
        hands.remove(id)
        apply()
    }

    /// Sets the cursor from the current count. The shell also calls this on every pointer
    /// move over the open panel, so a control that vanished under the pointer without an
    /// exit cannot leave a stale hand behind.
    public func apply() {
        (hands.isEmpty ? NSCursor.arrow : NSCursor.pointingHand).set()
    }

    /// The panel closed: nothing is hovered any more.
    public func reset() {
        hands.removeAll()
        NSCursor.arrow.set()
    }
}

private struct PointerOnHover: ViewModifier {
    let enabled: Bool
    @State private var id = UUID()
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                guard enabled, inside != hovering else { return }
                hovering = inside
                inside ? NotchPointer.shared.enter(id) : NotchPointer.shared.leave(id)
            }
            .onDisappear {
                guard hovering else { return }
                hovering = false
                NotchPointer.shared.leave(id)
            }
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

/// The music waveform. The idle shoulder and the music pane show the same element at two
/// sizes, so this is one drawing, not two: fixed-width capsule bars scaled to whatever
/// frame the caller gives it, dimmed and collapsed to a quiet row when nothing plays.
public struct NotchWaveform: View {
    private let levels: [Float]
    private let isPlaying: Bool

    public init(levels: [Float], isPlaying: Bool) {
        self.levels = levels
        self.isPlaying = isPlaying
    }

    /// The width the bars occupy naturally; callers that size the frame to the content
    /// use this instead of re-deriving bar arithmetic.
    public static func naturalWidth(barCount: Int) -> CGFloat {
        CGFloat(max(barCount * 2 - 1, 1)) * Metrics.waveformBarWidth
    }

    public var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: Metrics.waveformBarWidth) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Style.ink.opacity(isPlaying ? 0.85 : 0.35))
                        .frame(
                            width: Metrics.waveformBarWidth,
                            // The floor is the bar's thickness, not its width. A capsule
                            // clamped to its width is a circle, and a paused track must
                            // read as a flat quiet row, not a row of dots.
                            height: max(
                                geo.size.height * CGFloat(min(max(level, 0), 1)),
                                Metrics.waveformRestHeight
                            )
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .notchAnimation(Motion.ambient, value: levels)
        .accessibilityHidden(true)
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
        // The stroke straddles the path, so without this inset half the line width
        // hangs outside the frame and whatever contains the ring shaves its top.
        ZStack {
            Circle().stroke(Style.ink.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
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
