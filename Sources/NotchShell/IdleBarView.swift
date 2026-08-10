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
                IdleItemView(entry: pinned, namespace: namespace, isSource: isSource)
            }
            if let identity = composition.identity {
                IdleItemView(entry: identity, namespace: namespace, isSource: isSource)
            }
        }
        .padding(.horizontal, composition.hasLeading ? shoulderPadding : 0)
    }

    private var trailing: some View {
        RotorView(
            entries: composition.rotor,
            index: model.rotorIndex,
            namespace: namespace,
            isSource: isSource
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
    let namespace: Namespace.ID
    let isSource: Bool

    private var clamped: Int {
        entries.isEmpty ? 0 : min(max(index, 0), entries.count - 1)
    }

    var body: some View {
        ZStack {
            ForEach(Array(entries.enumerated()), id: \.offset) { offset, entry in
                IdleItemView(
                    entry: entry,
                    namespace: namespace,
                    isSource: isSource && offset == clamped
                )
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

/// The three travelling elements, rendered by the shell while the notch is closed.
///
/// Exactly one instance of each exists at any moment: while idle or in proximity these
/// are the rendered views, matched to the idle anchors. The moment the panel opens on
/// the music pane, the pane's own artwork, waveform and scrubber take over, and these
/// leave through the matched-geometry anchors in `ExpandedView`, which sit where the
/// pane lays those elements out. Rendering both at once is what put a second artwork
/// tile and a second progress line on screen.
///
/// The progress line alone also lives through the expanded phase whenever the landed
/// pane is not music: it follows `ExpandedView`'s border anchor along the panel's
/// bottom edge, and travels to the scrubber only when the user lands on music. It is
/// still the same single instance the whole way.
struct TravelLayer: View {
    let model: NotchShellModel
    let namespace: Namespace.ID

    private var showsBorderProgress: Bool {
        model.phase != .expanded || model.landed != .music
    }

    var body: some View {
        let artwork = model.travellingArtwork
        let composition = model.composition
        ZStack(alignment: .topLeading) {
            if model.phase != .expanded {
                if artwork.present {
                    ArtworkView(image: artwork.image)
                        .matchedGeometryEffect(
                            id: NotchTravelID.artwork.rawValue, in: namespace, isSource: false
                        )
                }
                if let levels = model.travellingWaveform {
                    // Playing is inferred from the levels themselves: the generator rests
                    // at 0.05, so anything meaningfully above that is live music.
                    NotchWaveform(
                        levels: levels,
                        isPlaying: levels.contains { $0 > 0.06 }
                    )
                    .matchedGeometryEffect(
                        id: NotchTravelID.waveform.rawValue, in: namespace, isSource: false
                    )
                }
            }
            if showsBorderProgress, let progress = composition.progress {
                NotchProgress(
                    value: progress,
                    height: Metrics.idleProgressHeight,
                    tint: Style.accent(for: composition.progressPane ?? model.focusedID),
                    // Music's accent is plain white. At full strength on a black notch
                    // that is a glowing stub, not a progress line.
                    prominence: 0.25
                )
                .matchedGeometryEffect(
                    id: NotchTravelID.progress.rawValue, in: namespace, isSource: false
                )
            }
        }
        .allowsHitTesting(false)
    }
}
