import NotchCore
import SwiftUI

/// A single line of text that scrolls only while the pointer is over it.
///
/// A permanently scrolling title is the single most annoying thing a music widget can do,
/// so the resting state is an ordinary tail-truncated line. Hovering reveals the rest and
/// nothing moves until then. Under Reduce Motion it never scrolls at all, and the user
/// still gets the full string as a tooltip.
struct MarqueeText: View {
    let text: String
    var font: Font = Style.title
    var color: Color = Style.ink

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var hovering = false

    /// `Motion` has no scrolling-speed token, so this is stated once here rather than
    /// scattered as literal durations. Points per second.
    private static let speed: CGFloat = 26
    private static let tailGap: CGFloat = 16

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }
    private var scrolling: Bool { hovering && overflow > 1 && !reduceMotion }
    private var travel: CGFloat { scrolling ? overflow + Self.tailGap : 0 }

    private var animation: Animation? {
        guard scrolling else { return Motion.reduced(Motion.tap) }
        let duration = Double(travel / Self.speed)
        return Animation.linear(duration: duration).delay(0.55).repeatForever(autoreverses: true)
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            // Only unclamped while scrolling. Same view either way, so this is the text
            // sliding rather than one label being swapped for another.
            .fixedSize(horizontal: scrolling, vertical: false)
            .offset(x: -travel)
            .animation(animation, value: travel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) { ruler }
            .clipped()
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .onHover { hovering = $0 }
            .help(overflow > 1 ? text : "")
            .accessibilityLabel(text)
    }

    /// Hidden copy at natural width, purely to learn whether the real one overflows.
    /// It sits in a background so it cannot affect layout.
    private var ruler: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
    }
}
