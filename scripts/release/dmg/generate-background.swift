#!/usr/bin/env swift
// Renders the DMG window background (brand artwork; see artwork/LICENSE.md).
//
// Usage: swift scripts/release/dmg/generate-background.swift [output-directory]
// Writes background.png (660x400 px) and background@2x.png (1320x800 px, 144 dpi) into the
// output directory (default: the directory containing this script). Both files are committed,
// so CI and release builds never need to render anything. Regenerate only when the design changes.
//
// Layout (points, origin top-left): app icon centre (170, 200), Applications centre (490, 200).
// These must match icon_locations in settings.py.
import AppKit

let width = 660.0
let height = 400.0

let cream = NSColor(srgbRed: 1.0, green: 0.973, blue: 0.94, alpha: 1)
let navy = NSColor(srgbRed: 0.11, green: 0.16, blue: 0.33, alpha: 1)
let blue = NSColor(srgbRed: 0.18, green: 0.48, blue: 0.96, alpha: 1)
let orange = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.10, alpha: 1)
let muted = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.55, alpha: 1)

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded),
       let font = NSFont(descriptor: descriptor, size: size) {
        return font
    }
    return base
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, centerX: Double, top: Double) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(at: NSPoint(x: centerX - size.width / 2, y: top))
}

func render(scale: Int, to url: URL) {
    let pixelsWide = Int(width) * scale
    let pixelsHigh = Int(height) * scale
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("cannot allocate bitmap") }
    // Points size drives the DPI metadata: 72 dpi at 1x, 144 dpi at 2x (needed by tiffutil -cathidpicheck).
    rep.size = NSSize(width: width, height: height)

    guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no graphics context") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let cg = gc.cgContext
    // Work in points with the origin at the top-left.
    // (The bitmap context already maps points to pixels via rep.size, so only flip the y axis.)
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current = flipped
    cg.setShouldAntialias(true)
    cg.setAllowsFontSmoothing(false) // grayscale text: identical on any Finder background

    // Background.
    cream.setFill()
    cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Title.
    drawCentered("Install TimeTug", font: roundedFont(size: 26, weight: .semibold),
                 color: navy, centerX: width / 2, top: 34)

    // Arrow: a soft arc from beside the app icon to beside the Applications icon.
    let start = CGPoint(x: 250, y: 208)
    let control = CGPoint(x: 330, y: 178)
    let end = CGPoint(x: 398, y: 206)
    let tangent = CGPoint(x: end.x - control.x, y: end.y - control.y)
    let len = (tangent.x * tangent.x + tangent.y * tangent.y).squareRoot()
    let dir = CGPoint(x: tangent.x / len, y: tangent.y / len)
    let normal = CGPoint(x: -dir.y, y: dir.x)

    // Shaft stops slightly short of the tip so the round cap does not poke through the head.
    let shaftEnd = CGPoint(x: end.x - dir.x * 10, y: end.y - dir.y * 10)
    cg.setStrokeColor(blue.cgColor)
    cg.setLineWidth(14)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.move(to: start)
    cg.addQuadCurve(to: shaftEnd, control: control)
    cg.strokePath()

    // Arrowhead: filled triangle with rounded corners (fill plus a round-joined stroke).
    let tip = CGPoint(x: end.x + dir.x * 14, y: end.y + dir.y * 14)
    let backCentre = CGPoint(x: end.x - dir.x * 18, y: end.y - dir.y * 18)
    let wing = 24.0
    let head = CGMutablePath()
    head.move(to: tip)
    head.addLine(to: CGPoint(x: backCentre.x + normal.x * wing, y: backCentre.y + normal.y * wing))
    head.addLine(to: CGPoint(x: backCentre.x - normal.x * wing, y: backCentre.y - normal.y * wing))
    head.closeSubpath()
    cg.setFillColor(blue.cgColor)
    cg.addPath(head)
    cg.fillPath()
    cg.setLineWidth(10)
    cg.addPath(head)
    cg.strokePath()

    // Orange sparks near the arrowhead (echo of the logo).
    cg.setStrokeColor(orange.cgColor)
    cg.setLineWidth(5)
    cg.setLineCap(.round)
    let sparkOrigin = CGPoint(x: tip.x + 2, y: tip.y - 36)
    for (angle, inner, outer) in [(-125.0, 6.0, 20.0), (-80.0, 8.0, 26.0), (-35.0, 6.0, 20.0)] {
        let a = angle * Double.pi / 180
        cg.move(to: CGPoint(x: sparkOrigin.x + cos(a) * inner, y: sparkOrigin.y + sin(a) * inner))
        cg.addLine(to: CGPoint(x: sparkOrigin.x + cos(a) * outer, y: sparkOrigin.y + sin(a) * outer))
    }
    cg.strokePath()

    // Instruction and tagline.
    drawCentered("Drag TimeTug to Applications", font: roundedFont(size: 18, weight: .semibold),
                 color: navy, centerX: width / 2, top: 312)
    drawCentered("A tug when time needs your attention.", font: roundedFont(size: 12, weight: .regular),
                 color: muted, centerX: width / 2, top: 366)

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
    do { try png.write(to: url) } catch { fatalError("cannot write \(url.path): \(error)") }
    print("Wrote \(url.path) (\(pixelsWide)x\(pixelsHigh))")
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let outDir = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : scriptDir
render(scale: 1, to: outDir.appendingPathComponent("background.png"))
render(scale: 2, to: outDir.appendingPathComponent("background@2x.png"))
