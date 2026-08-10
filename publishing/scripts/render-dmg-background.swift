// Renders the DMG window background: the notch as hardware at the top, an arrow
// guiding the app icon into Applications, and a caption.
//
// The finished window is laid out by create-dmg in release.sh: 660x400 points, the app
// icon centered at (180, 170) and the Applications link at (480, 170), measured from the
// top left. The artwork drawn here only decorates those fixed positions; nothing in the
// image is interactive.
//
// Usage: swift render-dmg-background.swift <output-dir>
// Writes background.png (660x400) and background@2x.png (1320x800) into <output-dir>.

import AppKit
import Foundation

let width: CGFloat = 660
let height: CGFloat = 400
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func render(scale: CGFloat, to path: String) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale),
        pixelsHigh: Int(height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("could not create bitmap") }

    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.scaleBy(x: scale, y: scale)

    // Background: the same deep vertical gradient as the app icon, near-black at the
    // top where the notch sits.
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.19, alpha: 1).cgColor,
        ] as CFArray,
        locations: [1, 0]
    )!
    ctx.drawLinearGradient(
        bg,
        start: CGPoint(x: width / 2, y: height),
        end: CGPoint(x: width / 2, y: 0),
        options: []
    )

    // The notch, hanging from the top edge with rounded bottom corners, exactly the
    // silhouette the app draws on screen.
    let notchWidth: CGFloat = 200
    let notchHeight: CGFloat = 24
    let notchRadius: CGFloat = 10
    let notch = CGMutablePath()
    let nx = (width - notchWidth) / 2
    let ny = height - notchHeight
    notch.move(to: CGPoint(x: nx, y: height))
    notch.addLine(to: CGPoint(x: nx, y: ny + notchRadius))
    notch.addArc(
        tangent1End: CGPoint(x: nx, y: ny),
        tangent2End: CGPoint(x: nx + notchRadius, y: ny),
        radius: notchRadius
    )
    notch.addLine(to: CGPoint(x: nx + notchWidth - notchRadius, y: ny))
    notch.addArc(
        tangent1End: CGPoint(x: nx + notchWidth, y: ny),
        tangent2End: CGPoint(x: nx + notchWidth, y: ny + notchRadius),
        radius: notchRadius
    )
    notch.addLine(to: CGPoint(x: nx + notchWidth, y: height))
    notch.closeSubpath()
    ctx.addPath(notch)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.addPath(notch)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.08).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()

    // The arrow between the two icon positions. Icon centers in this bottom-left
    // coordinate space: app at (180, 230), Applications at (480, 230), icons 128pt wide.
    let arrowY: CGFloat = 230
    let start = CGPoint(x: 268, y: arrowY)
    let end = CGPoint(x: 388, y: arrowY)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.35).cgColor)
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.move(to: start)
    ctx.addLine(to: CGPoint(x: end.x - 14, y: arrowY))
    ctx.strokePath()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: end.x - 22, y: arrowY + 13))
    head.addLine(to: end)
    head.addLine(to: CGPoint(x: end.x - 22, y: arrowY - 13))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.35).cgColor)
    ctx.fillPath()

    // Caption, centered near the bottom, clear of the icon labels.
    let caption = "Drag TopNotch into Applications" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.5),
    ]
    let textSize = caption.size(withAttributes: attrs)
    caption.draw(
        at: NSPoint(x: (width - textSize.width) / 2, y: 56),
        withAttributes: attrs
    )

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode png")
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

render(scale: 1, to: "\(out)/background.png")
render(scale: 2, to: "\(out)/background@2x.png")
