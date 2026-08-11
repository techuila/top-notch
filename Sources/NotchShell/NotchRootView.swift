import NotchCore
import SwiftUI

/// The single surface. One frame animates between the idle bar and the open panel; the
/// window itself never resizes, only this.
struct NotchRootView: View {
    let model: NotchShellModel
    let hitBox: NotchHitBox
    /// Fired whenever the pointer moves on or off the surface. A panel that never becomes
    /// key does not get `mouseMoved`, so the tracking area behind this is what keeps the
    /// open panel honest once the window has started accepting events.
    let onHover: (Bool) -> Void

    @Namespace private var travel
    @State private var idleWidth: CGFloat = 0

    private var isExpanded: Bool { model.phase == .expanded }

    private var surfaceWidth: CGFloat {
        isExpanded ? Metrics.expandedWidth : max(idleWidth, model.geometry.hardwareWidth)
    }

    private var surfaceHeight: CGFloat {
        switch model.phase {
        case .idle: ShellMetrics.idleHeight
        case .proximity: ShellMetrics.proximityHeight
        case .expanded: model.panelHeight
        }
    }

    private var cornerRadius: CGFloat {
        isExpanded ? Metrics.expandedCornerRadius : Metrics.idleCornerRadius
    }

    /// The concave top-corner fillets grow with the open morph, so the flare keeps its
    /// proportion against the panel instead of staying idle-sized against it.
    private var flareRadius: CGFloat {
        isExpanded ? Metrics.expandedFlareRadius : Metrics.flareRadius
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                ExpandedView(model: model, namespace: travel)
            } else {
                IdleBarView(
                    model: model,
                    composition: model.composition,
                    namespace: travel,
                    onWidth: { idleWidth = $0 }
                )
            }
        }
        .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
        .overlay(alignment: .topLeading) { TravelLayer(model: model, namespace: travel) }
        // The frame gains one fillet of width per side; the fillets flare into that
        // extra width at the very top, so the surface melts out of the screen edge
        // instead of being stamped on it. Padding by the current animated flare keeps
        // the frame in step with the growing fillets, and the material paints and
        // clips the full silhouette over that frame, wings included, so on expand the
        // flares wear the same surface as the body. One persistent shape morphing with
        // the phase, never an overlay; the fillets sit at the outer corners, far from
        // the camera housing, and at idle the material keeps the whole shape black.
        .padding(.horizontal, flareRadius)
        .notchMaterial(
            isExpanded: isExpanded, cornerRadius: cornerRadius, flareRadius: flareRadius
        )
        // Behind-window glass beneath the material's thinned scrim, masked to the full
        // silhouette. Structural, not alpha: at idle it leaves the hierarchy entirely,
        // so the window server stops backdrop sampling the moment the close morph
        // finishes. The opacity transition rides the same morph, so the surface
        // cross-dissolves in place instead of swapping. The mask is fixed at the
        // expanded radii; every cut it makes is deeper than any intermediate
        // silhouette's, so the glass never pokes past the drawn outline mid-morph.
        .background {
            if isExpanded, Appearance.shared.material != .solid {
                GlassBacking(
                    flareRadius: Metrics.expandedFlareRadius,
                    cornerRadius: Metrics.expandedCornerRadius
                )
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        // A pane asking the notch to acknowledge a moment. Anchored to the top because the
        // notch hangs off the top edge of the screen, so scaling from the centre would lift
        // it away from the bezel it is supposed to be part of.
        .phaseAnimator([1, ShellMetrics.pulseScale, 1], trigger: model.pulse) { view, scale in
            view.scaleEffect(scale, anchor: .top)
        } animation: { _ in
            Motion.reduced(Motion.tap)
        }
        .contentShape(
            NotchSilhouette(flareRadius: flareRadius, bottomRadius: cornerRadius)
        )
        .onContinuousHover { phase in
            switch phase {
            case .active: onHover(true)
            case .ended: onHover(false)
            }
        }
        .notchAnimation(Motion.morph, value: model.phase)
        .notchAnimation(Motion.morph, value: surfaceHeight)
        .environment(\.notchNamespace, travel)
        .environment(\.notchPhase, model.phase)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { hitBox.size = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
