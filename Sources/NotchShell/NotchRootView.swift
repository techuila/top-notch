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
            // The idle bar never unmounts; it fades with the phase. Structural
            // transitions proved untrustworthy here twice over: a removal-transition
            // view freezes and stops updating, so its matched-geometry anchors kept
            // claiming source mid-morph, and an `.identity` removal could linger
            // whole seconds after the phase flipped, drawing idle items on top of
            // the open panel. Plain animated opacity on a permanently mounted bar
            // has neither failure, its anchors stay live for the travelling
            // elements, and a handful of tiny idle views cost nothing while open.
            IdleBarView(
                model: model,
                composition: model.composition,
                namespace: travel,
                onWidth: { idleWidth = $0 }
            )
            .opacity(isExpanded ? 0 : 1)
            .allowsHitTesting(!isExpanded)

            // The pane content is the expensive side, so it still unmounts at idle
            // (cheap-when-idle). In with the morph; out fast, faster than the
            // shrink, so nothing rides the narrowing surface's edges.
            if isExpanded {
                ExpandedView(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.animation(Motion.reduced(Motion.tap))
                    ))
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
