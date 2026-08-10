import NotchCore
import SwiftUI

/// The outer outline of the black surface: a straight top edge that flares outward into
/// a concave quarter-fillet at each top corner, vertical sides, and the usual convex
/// rounding at the bottom. The fillets are what make the notch read as melting out of
/// the screen bezel instead of a rectangle stamped onto it, exactly like the hardware
/// cutout photographed from below.
///
/// The rect this fills is the body plus one fillet of width per side; the body is inset
/// by `flareRadius` so the fillets occupy the extra width in the top corners only. The
/// body outline is the same bottom-rounded continuous rectangle `NotchMaterial` draws,
/// so the two can never disagree about the bottom corners. Body and fillets are disjoint
/// subpaths of one `Path` filled in a single pass, which is what keeps the shared edge
/// free of an antialiasing seam.
struct NotchSilhouette: Shape {
    var flareRadius: CGFloat
    var bottomRadius: CGFloat

    /// The bottom radius morphs between the idle and expanded values with the phase.
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let flare = max(0, min(flareRadius, min(rect.width / 2, rect.height)))
        let body = rect.insetBy(dx: flare, dy: 0)
        var path = UnevenRoundedRectangle(
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            style: .continuous
        ).path(in: body)
        guard flare > 0 else { return path }

        // Left fillet. The sliver between the top edge, the body side and a quarter
        // circle centred outside the surface, tangent to both edges: the outline leaves
        // the screen edge flat and curves concavely down into the vertical side.
        path.move(to: CGPoint(x: body.minX, y: rect.minY + flare))
        path.addLine(to: CGPoint(x: body.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX, y: rect.minY + flare),
            radius: flare,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.closeSubpath()

        // Right fillet, mirrored.
        path.move(to: CGPoint(x: body.maxX, y: rect.minY + flare))
        path.addLine(to: CGPoint(x: body.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX, y: rect.minY + flare),
            radius: flare,
            startAngle: .degrees(-90),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.closeSubpath()

        return path
    }
}
