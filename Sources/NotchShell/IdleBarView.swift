import NotchCore
import SwiftUI

/// The closed notch.
///
/// Layout is three columns: left shoulder, a dead spacer exactly as wide as the camera
/// housing, right rotor. The bar sizes itself to its content and reports that width up, so
/// the black surface narrows around slots as they collapse rather than jumping.
struct IdleBarView: View {
    let model: NotchShellModel
    let composition: IdleComposition
    let namespace: Namespace.ID
    let onWidth: (CGFloat) -> Void

    private var isSource: Bool { model.phase != .expanded }

    private var shoulderPadding: CGFloat {
        model.phase == .proximity
            ? ShellMetrics.proximityShoulderPadding
            : ShellMetrics.idleShoulderPadding
    }

    /// Side of the expanded music tile, handed down so the artwork thumb's rounding
    /// stays proportional to the tile it stands in for.
    private var musicBand: CGFloat {
        model.pane(.music)?.contentHeight ?? Metrics.defaultPaneHeight
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
            // The camera housing. Nothing is ever drawn here.
            Color.clear.frame(width: model.geometry.hardwareWidth)
            trailing
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { progressAnchor }
        .notchAnimation(Motion.slot, value: composition)
        .notchAnimation(Motion.slot, value: shoulderPadding)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0) }
        .task(id: composition.rotor) {
            await model.runRotor(count: composition.rotor.count)
        }
    }

    private var leading: some View {
        HStack(spacing: Metrics.slotSpacing) {
            if let pinned = composition.pinned {
                IdleItemView(entry: pinned, artworkFullSize: musicBand)
            }
            if let identity = composition.identity {
                IdleItemView(entry: identity, artworkFullSize: musicBand)
            }
        }
        .padding(.horizontal, composition.hasLeading ? shoulderPadding : 0)
    }

    private var trailing: some View {
        RotorView(
            entries: composition.rotor,
            index: model.rotorIndex,
            artworkFullSize: musicBand
        )
        .padding(.horizontal, composition.rotor.isEmpty ? 0 : shoulderPadding)
    }

    @ViewBuilder private var progressAnchor: some View {
        if composition.progress != nil {
            Color.clear
                .frame(height: Metrics.idleProgressHeight)
                // Stops short of where the bottom corners curve away, so the line reads as
                // part of the notch edge instead of a bar running off the end of it.
                .padding(.horizontal, Metrics.idleProgressInset)
                .padding(.bottom, ShellMetrics.progressEdgeLift)
                .matchedGeometryEffect(
                    id: NotchTravelID.progress.rawValue, in: namespace, isSource: isSource
                )
        }
    }
}

/// The right shoulder. Items translate vertically through a clipped fixed-width window,
/// like a slot machine reel. Nothing ever cross-fades, and a single item never moves.
struct RotorView: View {
    let entries: [IdleEntry]
    let index: Int
    let artworkFullSize: CGFloat

    private var clamped: Int {
        entries.isEmpty ? 0 : min(max(index, 0), entries.count - 1)
    }

    var body: some View {
        ZStack {
            ForEach(Array(entries.enumerated()), id: \.offset) { offset, entry in
                IdleItemView(entry: entry, artworkFullSize: artworkFullSize)
                    .frame(width: Metrics.rotorWidth, height: Metrics.rotorHeight)
                    .offset(y: CGFloat(offset - clamped) * Metrics.rotorHeight)
            }
        }
        .frame(
            width: entries.isEmpty ? 0 : Metrics.rotorWidth,
            height: Metrics.rotorHeight
        )
        .clipped()
        .notchAnimation(Motion.rotate, value: clamped)
    }
}

/// The one element that lives through the open and close morphs: the bottom-edge
/// progress line.
///
/// The open and close transitions are a pure expand and shrink (owner decision):
/// artwork and waveform no longer fly between the idle slots and the pane's layout,
/// they are drawn in place by whichever state owns them and simply fade with it. The
/// progress line stays because it rides the surface's bottom edge rather than crossing
/// the panel: idle border, expanded border on non-music panes, and hidden while the
/// music pane's scrubber owns it. Exactly one instance, mounted continuously; its
/// border anchors move with the morphing surface and it follows them.
///
/// The expanded anchor lives here rather than in `ExpandedView` because a view fading
/// out with a transition no longer updates: an anchor frozen inside the removing panel
/// kept claiming `isSource` through the close and fought the idle bar's anchor. Here it
/// unmounts the instant the phase leaves `.expanded`, so exactly one side sources the
/// line's geometry at any moment of the morph.
struct TravelLayer: View {
    let model: NotchShellModel
    let namespace: Namespace.ID

    private var isExpanded: Bool { model.phase == .expanded }
    private var isOnMusic: Bool { model.landed == .music }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Identity transition: the anchor must register and unregister on the
            // exact frame the phase flips, never linger through a fade.
            if isExpanded {
                expandedProgressAnchor.transition(.identity)
            }

            if let progress = model.composition.progress {
                NotchProgress(
                    value: progress,
                    height: Metrics.idleProgressHeight,
                    tint: Style.accent(
                        for: model.composition.progressPane ?? model.focusedID
                    ),
                    // Music's accent is plain white. At full strength on a black notch
                    // that is a glowing stub, not a progress line.
                    prominence: 0.25
                )
                .matchedGeometryEffect(
                    id: NotchTravelID.progress.rawValue, in: namespace, isSource: false
                )
                .opacity(isExpanded && isOnMusic ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Where the line sits while the panel is open: the scrubber position on the music
    /// pane, the bottom border everywhere else. One anchor whose paddings move between
    /// the two, so the line follows a moving target instead of a remounting one; the
    /// border insets stop short of where the bottom corners curve away, matching the
    /// idle presentation of the same line.
    private var expandedProgressAnchor: some View {
        Color.clear
            .frame(height: Metrics.idleProgressHeight)
            .matchedGeometryEffect(
                id: NotchTravelID.progress.rawValue, in: namespace, isSource: true
            )
            .padding(
                .horizontal,
                isOnMusic ? Metrics.paneInset : ShellMetrics.expandedProgressInset
            )
            .padding(
                .bottom,
                isOnMusic ? Metrics.paneBottom : ShellMetrics.progressEdgeLift
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
