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
        case .idle: Metrics.idleHeight
        case .proximity: Metrics.proximityHeight
        case .expanded: model.panelHeight
        }
    }

    private var cornerRadius: CGFloat {
        isExpanded ? Metrics.expandedCornerRadius : Metrics.idleCornerRadius
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
        .notchMaterial(isExpanded: isExpanded, cornerRadius: cornerRadius)
        .contentShape(Rectangle())
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
