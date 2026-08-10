// Renders the TopNotch app icon: the notch as the whole mark, DynamicLake style, on the
// Teenage Engineering palette. Warm off-white card, one black notch pill with inverted
// top corners, orange waveform bars and a progress line inside it. Nothing else.
//
// A macOS icon supplies its own rounded-square canvas with margins; the system does not
// mask it.
//
// Usage: swift render-icon.swift <output-dir>
// Writes icon_1024.png into <output-dir>.

import AppKit
import Foundation

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// The palette, mirrored from NotchCore.Style by hand.
let cream = NSColor(calibratedRed: 0.93, green: 0.92, blue: 0.89, alpha: 1)
let black = NSColor(calibratedRed: 0.07, green: 0.068, blue: 0.065, alpha: 1)
let orange = NSColor(calibratedRed: 1.00, green: 0.30, blue: 0.00, alpha: 1)

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // macOS icon grid: the squircle occupies 824pt of a 1024pt canvas, 100pt margins.
    let inset: CGFloat = 100
    let card = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius: CGFloat = 185

    // Soft drop shadow behind the card, as the system icons carry.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14),
        blur: 44,
        color: NSColor.black.withAlphaComponent(0.30).cgColor
    )
    let cardPath = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(cardPath)
    ctx.setFillColor(cream.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()

    // A whisper of vertical shading so the card reads as moulded plastic, not flat paper.
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            cream.cgColor,
            NSColor(calibratedRed: 0.88, green: 0.87, blue: 0.84, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bg,
        start: CGPoint(x: size / 2, y: card.maxY),
        end: CGPoint(x: size / 2, y: card.minY),
        options: []
    )

    // The notch pill: hanging from the card's visual top, with the same inverted top
    // corners the app draws on screen. Flares curve outward where it meets the top band.
    let pillWidth: CGFloat = 620
    let pillHeight: CGFloat = 260
    let pillRadius: CGFloat = 96
    let flare: CGFloat = 56
    let pillTop = card.maxY - 128
    let px = (size - pillWidth) / 2
    let pillBottom = pillTop - pillHeight

    let pill = CGMutablePath()
    // Start at the left flare's outer tip on the top line.
    pill.move(to: CGPoint(x: px - flare, y: pillTop))
    // Concave curve inward and down into the left wall.
    pill.addQuadCurve(
        to: CGPoint(x: px, y: pillTop - flare),
        control: CGPoint(x: px, y: pillTop)
    )
    pill.addLine(to: CGPoint(x: px, y: pillBottom + pillRadius))
    pill.addArc(
        tangent1End: CGPoint(x: px, y: pillBottom),
        tangent2End: CGPoint(x: px + pillRadius, y: pillBottom),
        radius: pillRadius
    )
    pill.addLine(to: CGPoint(x: px + pillWidth - pillRadius, y: pillBottom))
    pill.addArc(
        tangent1End: CGPoint(x: px + pillWidth, y: pillBottom),
        tangent2End: CGPoint(x: px + pillWidth, y: pillBottom + pillRadius),
        radius: pillRadius
    )
    pill.addLine(to: CGPoint(x: px + pillWidth, y: pillTop - flare))
    // Concave curve up and outward onto the top line.
    pill.addQuadCurve(
        to: CGPoint(x: px + pillWidth + flare, y: pillTop),
        control: CGPoint(x: px + pillWidth, y: pillTop)
    )
    pill.closeSubpath()

    // The top band the pill hangs from, spanning the full card width: the screen edge.
    ctx.setFillColor(black.cgColor)
    ctx.fill(CGRect(x: card.minX, y: pillTop, width: card.width, height: card.maxY - pillTop))
    ctx.addPath(pill)
    ctx.fillPath()

    // Content sits between the pill's rounded corners.
    let interiorLeft = px + pillRadius
    let interiorRight = px + pillWidth - pillRadius
    let contentMidY = pillBottom + pillHeight * 0.56

    // Left: the album art tile, cream on black like a key on the EP-133.
    let tileSize: CGFloat = 128
    let tile = CGRect(
        x: interiorLeft, y: contentMidY - tileSize / 2, width: tileSize, height: tileSize
    )
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 30, cornerHeight: 30, transform: nil))
    ctx.setFillColor(cream.cgColor)
    ctx.fillPath()

    // Right: five orange waveform bars, like music playing.
    let barWidth: CGFloat = 26
    let barGap: CGFloat = 22
    let barHeights: [CGFloat] = [56, 100, 148, 88, 62]
    let barsTotal = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barGap
    var bx = interiorRight - barsTotal
    ctx.setFillColor(orange.cgColor)
    for h in barHeights {
        let bar = CGRect(x: bx, y: contentMidY - h / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        bx += barWidth + barGap
    }
    ctx.fillPath()

    // The progress line along the pill's bottom edge, mostly played, in orange.
    let lineY = pillBottom + 36
    let lineWidth = interiorRight - interiorLeft
    ctx.setFillColor(cream.withAlphaComponent(0.25).cgColor)
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: interiorLeft, y: lineY, width: lineWidth, height: 12),
        cornerWidth: 6, cornerHeight: 6, transform: nil
    ))
    ctx.fillPath()
    ctx.setFillColor(orange.cgColor)
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: interiorLeft, y: lineY, width: lineWidth * 0.62, height: 12),
        cornerWidth: 6, cornerHeight: 6, transform: nil
    ))
    ctx.fillPath()

    // A single small orange dot low right, the TE function-key wink that keeps the calm
    // lower field from reading as unfinished.
    ctx.setFillColor(orange.cgColor)
    ctx.addEllipse(in: CGRect(x: card.maxX - 196, y: card.minY + 132, width: 64, height: 64))
    ctx.fillPath()

    ctx.restoreGState()
    return true
}

var rect = CGRect(x: 0, y: 0, width: size, height: size)
guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
    fatalError("could not rasterize icon")
}
let rep = NSBitmapImageRep(cgImage: cg)
rep.size = NSSize(width: size, height: size)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode png")
}
try! png.write(to: URL(fileURLWithPath: "\(out)/icon_1024.png"))
print("wrote \(out)/icon_1024.png")
