// Draws the app icon (a white fermata on a slate-purple rounded square, after the
// original Fermata icon) and writes a 1024px PNG.
// Usage: swiftc scripts/make-icon.swift -o make-icon && ./make-icon out.png
import AppKit

let side = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Work in y-down coordinates.
ctx.translateBy(x: 0, y: CGFloat(side))
ctx.scaleBy(x: 1, y: -1)

// macOS icon grid: an 824pt rounded square centred in the 1024pt canvas.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
ctx.addPath(platePath)
ctx.setFillColor(CGColor(red: 0.29, green: 0.275, blue: 0.376, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let colors = [
    CGColor(red: 0.376, green: 0.361, blue: 0.467, alpha: 1),
    CGColor(red: 0.227, green: 0.212, blue: 0.298, alpha: 1),
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.maxY), options: [])
ctx.restoreGState()

// Fermata glyph, defined around (0,0) in a 120pt design space.
let scale: CGFloat = 824.0 / 120.0
ctx.translateBy(x: 512, y: 512 + 3 * scale)
ctx.scaleBy(x: scale, y: scale)
ctx.setFillColor(CGColor(red: 0.957, green: 0.949, blue: 0.973, alpha: 1))

ctx.move(to: CGPoint(x: -38, y: 14))
ctx.addCurve(to: CGPoint(x: 38, y: 14), control1: CGPoint(x: -38, y: -42), control2: CGPoint(x: 38, y: -42))
ctx.addCurve(to: CGPoint(x: -38, y: 14), control1: CGPoint(x: 28, y: -18), control2: CGPoint(x: -28, y: -18))
ctx.closePath()
ctx.fillPath()
ctx.fillEllipse(in: CGRect(x: -9, y: -1, width: 18, height: 18))

NSGraphicsContext.current = nil
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
