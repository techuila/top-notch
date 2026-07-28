import NotchCore
import SwiftUI

/// The open panel: pill row, then the horizontally paging pane host, plus the landing
/// anchors the travelling elements move to.
struct ExpandedView: View {
    let model: NotchShellModel
    let namespace: Namespace.ID

    /// `Metrics.paneTop` is measured from the top of the panel, so the gap under the pills
    /// is whatever is left after the pill band.
    private var pillToPaneGap: CGFloat {
        max(Metrics.paneTop - Metrics.pillRowTop - Metrics.pillRowHeight, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            PillRow(model: model)
                .frame(height: Metrics.pillRowHeight)
                .padding(.top, Metrics.pillRowTop)
                .padding(.bottom, pillToPaneGap)
            PaneHost(model: model)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topLeading) { artworkAnchor }
        .overlay(alignment: .topTrailing) { waveformAnchor }
        .overlay(alignment: .bottom) { progressAnchor }
    }

    private var artworkAnchor: some View {
        Color.clear
            .frame(width: ShellMetrics.expandedArtwork, height: ShellMetrics.expandedArtwork)
            .matchedGeometryEffect(
                id: NotchTravelID.artwork.rawValue, in: namespace, isSource: true
            )
            .padding(.leading, Metrics.paneInset)
            .padding(.top, Metrics.paneTop)
            .allowsHitTesting(false)
    }

    private var waveformAnchor: some View {
        Color.clear
            .frame(width: ShellMetrics.expandedWaveWidth, height: ShellMetrics.expandedWaveHeight)
            .matchedGeometryEffect(
                id: NotchTravelID.waveform.rawValue, in: namespace, isSource: true
            )
            .padding(.trailing, Metrics.paneInset)
            .padding(.top, Metrics.paneTop)
            .allowsHitTesting(false)
    }

    /// On open the bottom-edge line detaches from the border and becomes the scrubber.
    private var progressAnchor: some View {
        Color.clear
            .frame(height: Metrics.idleProgressHeight)
            .matchedGeometryEffect(
                id: NotchTravelID.progress.rawValue, in: namespace, isSource: true
            )
            .padding(.horizontal, Metrics.paneInset)
            .padding(.bottom, Metrics.paneBottom)
            .allowsHitTesting(false)
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

/// Horizontally paging pane host. Snap comes from `.viewAligned`, momentum from the real
/// scroll view underneath, and the indicator is never drawn.
struct PaneHost: View {
    @Bindable var model: NotchShellModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // Identity must be `PaneID` itself, not `PaneID.id`, or the scroll position
                // binding has nothing to match against and programmatic jumps do nothing.
                LazyHStack(spacing: 0) {
                    ForEach(model.order, id: \.self) { id in
                        PaneSlot(model: model, id: id)
                            .frame(width: Metrics.expandedWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden, axes: [.horizontal, .vertical])
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $model.scrollTarget)
            .task {
                // A scroll view acts on a change of position, not on the value it is born
                // holding, so opening on anything but the first pane has to be asserted
                // once the content exists. Unanimated: this is the opening frame.
                await Task.yield()
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(model.landed, anchor: .center)
                }
            }
        }
        .frame(height: model.landedContentHeight)
        .notchAnimation(Motion.morph, value: model.landedContentHeight)
    }
}

/// Wraps a pane's own content. The `AnyView` is forced by the `NotchPane` contract and is
/// confined to the expanded path, never the idle bar.
struct PaneSlot: View {
    let model: NotchShellModel
    let id: PaneID

    var body: some View {
        Group {
            if let pane = model.pane(id) {
                pane.content()
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
