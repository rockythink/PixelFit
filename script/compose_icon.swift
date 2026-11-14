// Composes the macOS app icon from full-bleed square artwork: an 824 pt continuous-corner tile
// on a 1024 canvas with the system-style drop shadow (Apple's macOS icon grid).
// Usage: swift script/compose_icon.swift <artwork.png> <output.png>
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let artwork = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: compose_icon.swift <artwork.png> <output.png>\n".utf8))
    exit(1)
}

let canvas = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
guard let context = CGContext(
    data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

/// Continuous-curvature corners: a superellipse-like path rather than circular arcs.
func squircle(in rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let k: CGFloat = 1.28 // extends the corner transition along each edge, as in Apple's tiles
    let r = radius
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    path.move(to: CGPoint(x: minX + r * k, y: minY))
    path.addLine(to: CGPoint(x: maxX - r * k, y: minY))
    path.addCurve(to: CGPoint(x: maxX, y: minY + r * k),
                  control1: CGPoint(x: maxX - r * 0.36, y: minY), control2: CGPoint(x: maxX, y: minY + r * 0.36))
    path.addLine(to: CGPoint(x: maxX, y: maxY - r * k))
    path.addCurve(to: CGPoint(x: maxX - r * k, y: maxY),
                  control1: CGPoint(x: maxX, y: maxY - r * 0.36), control2: CGPoint(x: maxX - r * 0.36, y: maxY))
    path.addLine(to: CGPoint(x: minX + r * k, y: maxY))
    path.addCurve(to: CGPoint(x: minX, y: maxY - r * k),
                  control1: CGPoint(x: minX + r * 0.36, y: maxY), control2: CGPoint(x: minX, y: maxY - r * 0.36))
    path.addLine(to: CGPoint(x: minX, y: minY + r * k))
    path.addCurve(to: CGPoint(x: minX + r * k, y: minY),
                  control1: CGPoint(x: minX, y: minY + r * 0.36), control2: CGPoint(x: minX + r * 0.36, y: minY))
    path.closeSubpath()
    return path
}

let shape = squircle(in: tile, radius: 185)

// Shadow: drawn under an opaque tile, offset downward (CG's y axis points up).
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.32))
context.addPath(shape)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
context.interpolationQuality = .high
context.draw(artwork, in: tile)
// Hairline inner rim keeps the edge crisp on dark Docks.
context.addPath(squircle(in: tile.insetBy(dx: 1, dy: 1), radius: 184))
context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
context.setLineWidth(2)
context.strokePath()
context.restoreGState()

guard let image = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: arguments[2]))
