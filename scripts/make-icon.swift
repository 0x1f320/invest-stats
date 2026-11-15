// Draws the app icon with Core Graphics and writes Resources/AppIcon.icns.
//
// Usage: swift scripts/make-icon.swift
//
// The icon is a dark menu bar with a red ▲ item, and a popover hanging from that item with a
// rising chart. It follows the macOS icon grid: a 1024 pt canvas with an 824 pt continuous-corner
// rounded square, inset by 100 pt for the drop shadow. Coordinates below are in that 1024 pt
// space with the origin at the top left.
import AppKit
import CoreGraphics
import Foundation

let red = CGColor(srgbRed: 0xF0 / 255, green: 0x44 / 255, blue: 0x52 / 255, alpha: 1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

/// A rounded rectangle with continuous (squircle) corners, matching the macOS icon shape.
func continuousRoundedRect(_ rect: CGRect, radius r: CGFloat) -> CGPath {
    // Bezier coefficients of a continuous corner, relative to the radius.
    let a: CGFloat = 1.52866483, b: CGFloat = 1.08849323, c: CGFloat = 0.86840689
    let d: CGFloat = 0.66993427, e: CGFloat = 0.06549600, f: CGFloat = 0.02248807
    let g: CGFloat = 0.63149399, h: CGFloat = 0.07491100, i: CGFloat = 0.37282392
    let j: CGFloat = 0.16905220

    let path = CGMutablePath()
    // Draws one corner. `p` maps (along the edge, toward the next edge) offsets from the corner.
    func corner(_ p: (CGFloat, CGFloat) -> CGPoint) {
        path.addLine(to: p(a * r, 0))
        path.addCurve(to: p(d * r, e * r), control1: p(b * r, 0), control2: p(c * r, f * r))
        path.addLine(to: p(g * r, h * r))
        path.addCurve(to: p(h * r, g * r), control1: p(i * r, j * r), control2: p(j * r, i * r))
        path.addLine(to: p(e * r, d * r))
        path.addCurve(to: p(0, a * r), control1: p(f * r, c * r), control2: p(0, b * r))
    }
    let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    path.move(to: CGPoint(x: x0 + a * r, y: y0))
    corner { CGPoint(x: x1 - $0, y: y0 + $1) }  // top right
    corner { CGPoint(x: x1 - $1, y: y1 - $0) }  // bottom right
    corner { CGPoint(x: x0 + $0, y: y1 - $1) }  // bottom left
    corner { CGPoint(x: x0 + $1, y: y0 + $0) }  // top left
    path.closeSubpath()
    return path
}

/// The popover: a rounded card with a caret on its top edge at `caretX`.
func popover(_ rect: CGRect, radius r: CGFloat, caretX: CGFloat, caret: CGFloat) -> CGPath {
    let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x0, y: y0 + r))
    path.addQuadCurve(to: CGPoint(x: x0 + r, y: y0), control: CGPoint(x: x0, y: y0))
    path.addLine(to: CGPoint(x: caretX - caret, y: y0))
    path.addLine(to: CGPoint(x: caretX, y: y0 - caret))
    path.addLine(to: CGPoint(x: caretX + caret, y: y0))
    path.addLine(to: CGPoint(x: x1 - r, y: y0))
    path.addQuadCurve(to: CGPoint(x: x1, y: y0 + r), control: CGPoint(x: x1, y: y0))
    path.addLine(to: CGPoint(x: x1, y: y1 - r))
    path.addQuadCurve(to: CGPoint(x: x1 - r, y: y1), control: CGPoint(x: x1, y: y1))
    path.addLine(to: CGPoint(x: x0 + r, y: y1))
    path.addQuadCurve(to: CGPoint(x: x0, y: y1 - r), control: CGPoint(x: x0, y: y1))
    path.closeSubpath()
    return path
}

func verticalGradient(_ top: CGColor, _ bottom: CGColor) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray,
        locations: [0, 1])!
}

/// Renders the icon at `pixels` × `pixels`.
func render(pixels: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    // Shadows ignore the transform, so their offset and blur are scaled by hand.
    // In device space, a negative y offset points down.
    func shadow(y: CGFloat, blur: CGFloat, _ color: CGColor) {
        ctx.setShadow(offset: CGSize(width: 0, height: -y * scale), blur: blur * scale, color: color)
    }
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.interpolationQuality = .high

    let squircle = continuousRoundedRect(
        CGRect(x: 100, y: 100, width: 824, height: 824), radius: 185.4)

    // Drop shadow under the whole icon.
    ctx.saveGState()
    shadow(y: 12, blur: 28, color(0x000000, 0.28))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0xDCE4EF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Background.
    ctx.drawLinearGradient(
        verticalGradient(color(0xF4F7FB), color(0xDCE4EF)),
        start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

    // Menu bar with one ▲ item.
    ctx.setFillColor(color(0x151C2B))
    ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 190))
    ctx.move(to: CGPoint(x: 630, y: 232))
    ctx.addLine(to: CGPoint(x: 680, y: 158))
    ctx.addLine(to: CGPoint(x: 730, y: 232))
    ctx.closePath()
    ctx.setFillColor(red)
    ctx.fillPath()

    // Popover hanging from the ▲ item.
    ctx.saveGState()
    shadow(y: 18, blur: 48, color(0x1B2B4B, 0.22))
    ctx.addPath(
        popover(
            CGRect(x: 190, y: 340, width: 644, height: 510), radius: 56, caretX: 680, caret: 44))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Rising chart: a soft fill under a thick line.
    let points = [
        CGPoint(x: 280, y: 700), CGPoint(x: 440, y: 600), CGPoint(x: 560, y: 660),
        CGPoint(x: 744, y: 470),
    ]
    let baseline: CGFloat = 790
    ctx.saveGState()
    ctx.addLines(between: points)
    ctx.addLine(to: CGPoint(x: points.last!.x, y: baseline))
    ctx.addLine(to: CGPoint(x: points[0].x, y: baseline))
    ctx.closePath()
    ctx.clip()
    ctx.drawLinearGradient(
        verticalGradient(red.copy(alpha: 0.32)!, red.copy(alpha: 0)!),
        start: CGPoint(x: 0, y: 470), end: CGPoint(x: 0, y: baseline), options: [])
    ctx.restoreGState()

    ctx.addLines(between: points)
    ctx.setStrokeColor(red)
    ctx.setLineWidth(52)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    ctx.restoreGState()

    // Hairline rim.
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.12))
    ctx.setLineWidth(4)
    ctx.strokePath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try writePNG(
        render(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(
        render(pixels: points * 2),
        to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("Wrote \(output.path)")
