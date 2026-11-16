import AppKit

/// Menu bar icon.
/// - Off: "zZ" above a flat line (lid closed, Mac asleep).
/// - On: a fermata arc as a laptop lid over a base line, with a green dot (the
///   "still on" light). The dot is drawn separately by `StatusDotView`, so the rest
///   can stay a template image that macOS tints to suit the menu bar.
enum StatusIcon {
    static let size = NSSize(width: 20, height: 15)

    // Glyph space: x in -46...46, y in -28...36 (y down), centred on (0, 4).
    private static let dotCenter = NSPoint(x: 0, y: 9)
    private static let dotRadius: CGFloat = 12

    private static func scale(for size: NSSize) -> CGFloat {
        min(size.width / 96, size.height / 66)
    }

    /// Where the green dot sits inside an icon of `size`, in y-down coordinates.
    static func dotRect(in size: NSSize) -> NSRect {
        let s = scale(for: size)
        let r = dotRadius * s
        let cx = size.width / 2 + dotCenter.x * s
        let cy = size.height / 2 + (dotCenter.y - 4) * s
        return NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
    }

    static func image(active: Bool, size: NSSize = StatusIcon.size) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            let s = scale(for: rect.size)
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY - 4 * s)
            transform.scale(by: s)
            transform.concat()

            NSColor.black.set()

            NSBezierPath(roundedRect: NSRect(x: -46, y: 28, width: 92, height: 8),
                         xRadius: 4, yRadius: 4).fill()

            if active {
                let arc = NSBezierPath()
                arc.move(to: NSPoint(x: -38, y: 14))
                arc.curve(to: NSPoint(x: 38, y: 14),
                          controlPoint1: NSPoint(x: -38, y: -42), controlPoint2: NSPoint(x: 38, y: -42))
                arc.curve(to: NSPoint(x: -38, y: 14),
                          controlPoint1: NSPoint(x: 28, y: -18), controlPoint2: NSPoint(x: -28, y: -18))
                arc.close()
                arc.fill()
            } else {
                strokeZ(center: NSPoint(x: -20, y: 8), half: 9, lineWidth: 6)
                strokeZ(center: NSPoint(x: 18, y: -9), half: 15, lineWidth: 7.5)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func strokeZ(center: NSPoint, half: CGFloat, lineWidth: CGFloat) {
        let z = NSBezierPath()
        z.move(to: NSPoint(x: center.x - half, y: center.y - half))
        z.line(to: NSPoint(x: center.x + half, y: center.y - half))
        z.line(to: NSPoint(x: center.x - half, y: center.y + half))
        z.line(to: NSPoint(x: center.x + half, y: center.y + half))
        z.lineWidth = lineWidth
        z.lineCapStyle = .round
        z.lineJoinStyle = .round
        z.stroke()
    }
}

/// The green dot, laid over the status item button while sleep is being prevented.
final class StatusDotView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: StatusIcon.dotRect(in: bounds.size)).fill()
    }

    // Clicks go through to the status item button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
