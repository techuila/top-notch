// Renders the TopNotch app icon: the notch itself, drawn as hardware.
//
// A macOS icon supplies its own rounded-square canvas with margins; the system does not
// mask it. The design is the top edge of a dark display with the notch cut into it and
// the app's three accent colours as idle content beside it, which is the app in one shape.
//
// Usage: swift render-icon.swift <output-dir>
// Writes icon_1024.png into <output-dir>.

import AppKit
import Foundation

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

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
        color: NSColor.black.withAlphaComponent(0.35).cgColor
    )
    let cardPath = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(cardPath)
    ctx.setFillColor(NSColor(calibratedWhite: 0.09, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Background: a deep vertical gradient, near-black at the top where the notch lives.
    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.19, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bg,
        start: CGPoint(x: size / 2, y: card.minY),
        end: CGPoint(x: size / 2, y: card.maxY),
        options: []
    )

    // The notch: a black bar hanging from the card's top edge, bottom corners rounded,
    // exactly the silhouette the app draws on screen.
    let notchWidth: CGFloat = 450
    let notchHeight: CGFloat = 175
    let notchRadius: CGFloat = 72
    let notch = CGMutablePath()
    let nx = (size - notchWidth) / 2
    let ny = card.maxY - notchHeight
    notch.move(to: CGPoint(x: nx, y: card.maxY))
    notch.addLine(to: CGPoint(x: nx, y: ny + notchRadius))
    notch.addArc(
        center: CGPoint(x: nx + notchRadius, y: ny + notchRadius),
        radius: notchRadius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false
    )
    notch.addLine(to: CGPoint(x: nx + notchWidth - notchRadius, y: ny))
    notch.addArc(
        center: CGPoint(x: nx + notchWidth - notchRadius, y: ny + notchRadius),
        radius: notchRadius, startAngle: .pi * 1.5, endAngle: 0, clockwise: false
    )
    notch.addLine(to: CGPoint(x: nx + notchWidth, y: card.maxY))
    notch.closeSubpath()
    ctx.addPath(notch)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()

    // A hairline of screen light along the top edge either side of the notch, so the
    // black reads as a cutout in a display rather than a floating lozenge.
    ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.16).cgColor)
    ctx.fill(CGRect(x: card.minX, y: card.maxY - 4, width: nx - card.minX, height: 4))
    ctx.fill(CGRect(x: nx + notchWidth, y: card.maxY - 4, width: card.maxX - nx - notchWidth, height: 4))

    // Idle content in the shoulders: an artwork square on the left, waveform on the
    // right, in the app's real accent colours.
    let contentY = ny + (notchHeight - 66) / 2

    // Artwork chip.
    let art = CGRect(x: nx + 56, y: contentY, width: 66, height: 66)
    let artPath = CGPath(roundedRect: art, cornerWidth: 19, cornerHeight: 19, transform: nil)
    ctx.addPath(artPath)
    ctx.setFillColor(NSColor(calibratedRed: 0.72, green: 0.66, blue: 1.00, alpha: 1).cgColor)
    ctx.fillPath()

    // Waveform: five bars, the house standard.
    let barHeights: [CGFloat] = [26, 50, 66, 42, 30]
    let barWidth: CGFloat = 14
    let gap: CGFloat = 11
    let waveWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * gap
    var bx = nx + notchWidth - 56 - waveWidth
    for h in barHeights {
        let bar = CGRect(x: bx, y: ny + (notchHeight - h) / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        bx += barWidth + gap
    }
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()

    // The progress line along the notch bottom edge, in the pomodoro accent.
    let line = CGRect(x: nx + 48, y: ny - 16, width: notchWidth - 112, height: 12)
    ctx.addPath(CGPath(roundedRect: line, cornerWidth: 6, cornerHeight: 6, transform: nil))
    ctx.setFillColor(NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.29, alpha: 1).cgColor)
    ctx.fillPath()

    ctx.restoreGState()
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("error: could not render icon\n".utf8))
    exit(1)
}

let path = "\(out)/icon_1024.png"
try png.write(to: URL(fileURLWithPath: path))
print("wrote \(path)")
