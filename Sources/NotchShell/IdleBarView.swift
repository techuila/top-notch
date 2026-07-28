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
        model.phase == .proximity ? Metrics.proximityShoulderPadding : Metrics.shoulderPadding
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

/// The three persistent elements, rendered once and positioned by matched geometry.
/// They are the same views in both states, which is what makes the open look like a move
/// rather than a swap.
struct TravelLayer: View {
    let model: NotchShellModel
    let namespace: Namespace.ID

    var body: some View {
        let artwork = model.travellingArtwork
        ZStack(alignment: .topLeading) {
            if artwork.present {
                ArtworkView(image: artwork.image)
                    .matchedGeometryEffect(
                        id: NotchTravelID.artwork.rawValue, in: namespace, isSource: false
                    )
            }
            if let levels = model.travellingWaveform {
                WaveformView(levels: levels)
                    .matchedGeometryEffect(
                        id: NotchTravelID.waveform.rawValue, in: namespace, isSource: false
                    )
            }
            if let progress = model.composition.progress {
                NotchProgress(
                    value: progress,
                    height: Metrics.idleProgressHeight,
                    tint: Style.accent(for: model.focusedID)
                )
                .matchedGeometryEffect(
                    id: NotchTravelID.progress.rawValue, in: namespace, isSource: false
                )
            }
        }
        .allowsHitTesting(false)
    }
}
