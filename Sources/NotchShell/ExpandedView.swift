import NotchCore
import SwiftUI

/// The open panel: pill row, then the horizontally paging pane host. The progress
/// line's expanded anchor lives in `TravelLayer`, not here: a view fading out with a
/// transition no longer updates, so an anchor mounted in this panel would keep
/// claiming its source role all through the close morph and fight the idle bar's.
struct ExpandedView: View {
    let model: NotchShellModel

    /// `Metrics.paneTop` is measured from the top of the panel, so the gap under the pills
    /// is whatever is left after the pill band.
    private var pillToPaneGap: CGFloat {
        max(Metrics.paneTop - Metrics.pillRowTop - Metrics.pillRowHeight, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            PillRow(model: model)
                .frame(height: Metrics.pillRowHeight)
                .padding(.top, Metrics.pillRowTop + ShellMetrics.pillBreathingRoom)
                .padding(.bottom, pillToPaneGap)
            PaneHost(model: model)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One pill per pane. The selected one jumps the host to that pane.
struct PillRow: View {
    let model: NotchShellModel

    var body: some View {
        HStack(spacing: ShellMetrics.pillSpacing) {
            ForEach(model.order) { id in
                PillView(pane: id, selected: model.landed == id) {
                    withAnimation(Motion.reduced(Motion.morph)) { model.land(on: id) }
                }
            }
        }
    }
}

struct PillView: View {
    let pane: PaneID
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    private var fill: Color {
        if selected { return Style.fillActive }
        return hovering ? Style.fillHover : Style.fill
    }

    var body: some View {
        Text(pane.title)
            .font(Style.label)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(selected ? Style.onActive : Style.inkFaint)
            .padding(.horizontal, ShellMetrics.pillInset)
            .frame(height: Metrics.pillRowHeight)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .notchAnimation(Motion.tap, value: hovering)
            .notchAnimation(Motion.morph, value: selected)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(pane.title)
    }
}

/// The pane strip, offset-driven: every pane sits in one row and the row is translated
/// so the landed pane fills the viewport, with everything else clipped away. This
/// replaced the scroll-view host (owner decision, 2026-08-12): a scroll viewport can be
/// born mispositioned, and however hard the open asserted the position it kept showing
/// the leftmost pane (music) under another pane's selected pill. Offset math cannot be
/// mispositioned - the landed pane is shown, always - and a pane change still reads as
/// the strip sliding, never a swap. Swipes and wheel steps land through the shell's
/// wheel monitor; pills jump directly.
struct PaneHost: View {
    let model: NotchShellModel

    private var index: Int {
        model.order.firstIndex(of: model.landed) ?? 0
    }

    var body: some View {
        // Top alignment so a pane taller than the landed one hangs below the host and
        // is clipped there, never shoved up under the pill row.
        HStack(alignment: .top, spacing: 0) {
            ForEach(model.order, id: \.self) { id in
                PaneSlot(model: model, id: id)
            }
        }
        .offset(x: -CGFloat(index) * Metrics.expandedWidth)
        .frame(
            width: Metrics.expandedWidth,
            height: model.landedContentHeight,
            alignment: .topLeading
        )
        .clipped()
        .notchAnimation(Motion.morph, value: index)
        .notchAnimation(Motion.morph, value: model.landedContentHeight)
    }
}

/// Wraps a pane's own content. The `AnyView` is forced by the `NotchPane` contract and is
/// confined to the expanded path, never the idle bar.
///
/// Each slot is exactly as tall as its own pane's declared content height, not the landed
/// pane's. Squeezing every slot to the landed height centred any taller neighbour and cut
/// it off at the top; at its own height a pane always fits once it lands, and mid-swipe a
/// taller neighbour is clipped only at the bottom until the panel morphs up to meet it.
struct PaneSlot: View {
    let model: NotchShellModel
    let id: PaneID

    private var height: CGFloat {
        model.pane(id)?.contentHeight ?? Metrics.defaultPaneHeight
    }

    var body: some View {
        Group {
            if let pane = model.pane(id) {
                pane.content()
            } else {
                Color.clear
            }
        }
        .frame(width: Metrics.expandedWidth, height: height, alignment: .top)
        .notchAnimation(Motion.morph, value: height)
    }
}
