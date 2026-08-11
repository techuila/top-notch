import AppKit
import NotchCore
import SwiftUI

/// The behind-window glass under the open panel.
///
/// The notch window is transparent and borderless, so an in-window material has nothing
/// behind it to refract: SwiftUI's glassEffect and AppKit's NSGlassEffectView both
/// composite within their own window and come out reading as a solid dark fill here.
/// NSVisualEffectView with `.behindWindow` blending is the one API that samples what is
/// behind the window itself, which is what makes other apps show through the panel.
///
/// The view exists only while the shell mounts it: the panel open in a glass-family
/// mode. Backdrop sampling keeps the window server compositing continuously, which is
/// acceptable for an open panel and forbidden at idle, so idle removes the view from
/// the hierarchy entirely rather than hiding it.
struct GlassBacking: NSViewRepresentable {
    /// Concave top-corner fillet radius of the full silhouette the mask reproduces.
    var flareRadius: CGFloat
    /// Convex bottom corner radius, matching what `NotchMaterial` clips to.
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassthroughGlassView()
        view.blendingMode = .behindWindow
        view.state = .active
        // Of the behind-window materials, hudWindow is the one that still reads as dark
        // glass over a bright desktop; underWindowBackground resolves too light and
        // washes the panel out. The notch is always dark by design, so the appearance
        // is pinned rather than following the system.
        view.material = .hudWindow
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.silhouetteMask(flare: flareRadius, bottom: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // The radii are constants while the view exists (glass only backs the expanded
        // panel), but stay honest if the tokens ever change between mounts.
        if view.maskImage?.capInsets.left != flareRadius + Self.reach(of: cornerRadius) {
            view.maskImage = Self.silhouetteMask(flare: flareRadius, bottom: cornerRadius)
        }
    }

    /// How far a continuous corner influences the edges around it. Apple's squircle
    /// blends over roughly 1.53x its radius, so the preserved cap regions must extend
    /// that far or the stretch band would deform the curve's tail.
    private static func reach(of radius: CGFloat) -> CGFloat {
        (radius * 1.53).rounded(.up)
    }

    /// A resizable mask of the full silhouette: concave fillets in the top corners,
    /// convex rounding in the bottom ones, straight bands between. Cap insets preserve
    /// the four corner regions and leave one point of stretch in each axis, so this
    /// single small image follows every size the open morph passes through and nothing
    /// is regenerated frame to frame. Drawn through `NotchSilhouette` itself, so the
    /// glass edge and the material's paint can never disagree about the outline.
    private static func silhouetteMask(flare: CGFloat, bottom: CGFloat) -> NSImage {
        let reach = reach(of: bottom)
        let cap = flare + reach
        let size = NSSize(width: cap * 2 + 1, height: flare + reach + 1)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(
                NotchSilhouette(flareRadius: flare, bottomRadius: bottom)
                    .path(in: rect).cgPath
            )
            context.setFillColor(CGColor.black)
            context.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: flare, left: cap, bottom: reach, right: cap)
        image.resizingMode = .stretch
        return image
    }
}

/// The window is nonactivating and inert at idle; the backing must never change that.
/// It refuses every hit so clicks pass through it exactly as they did before it existed.
private final class PassthroughGlassView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
