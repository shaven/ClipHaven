import AppKit

/// ClipHaven's coloured icon, for the menu bar and the app: a blue clipboard with a white sheet,
/// three bright clip lines and a gold clip. Drawn in code, so it stays sharp at every size.
enum ColourIcon {
    /// For the menu bar. Not a template image: the colours are shown as they are.
    static func menuBar(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, margin: 0)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "ClipHaven"
        return image
    }

    /// A square PNG of `pixels` for the app icon; macOS leaves a margin around app artwork.
    static func png(pixels: Int, forApp: Bool) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let side = CGFloat(pixels)
        draw(in: NSRect(x: 0, y: 0, width: side, height: side), margin: forApp ? side * 0.1 : 0)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Draws on an 18-point grid fitted into `rect` less `margin` on each side.
    private static func draw(in rect: NSRect, margin: CGFloat) {
        let art = rect.insetBy(dx: margin, dy: margin)
        let s = art.width / 18
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: art.minX + x * s, y: art.minY + y * s, width: w * s, height: h * s)
        }

        // Board.
        let board = NSBezierPath(roundedRect: r(1.6, 0.4, 14.8, 15.4), xRadius: 3.2 * s, yRadius: 3.2 * s)
        NSGradient(starting: color(0x5BA4FF), ending: color(0x2D5BE3))?.draw(in: board, angle: -90)
        color(0x1E3FB5).withAlphaComponent(0.55).setStroke()
        board.lineWidth = 0.7 * s
        board.stroke()

        // Sheet.
        color(0xFFFFFF).setFill()
        NSBezierPath(roundedRect: r(3.7, 2, 10.6, 11.2), xRadius: 1.6 * s, yRadius: 1.6 * s).fill()

        // Clip lines, one bright colour each.
        for (y, width, hex) in [(10.0, 7.4, 0xFF9F0A as UInt32), (7.3, 6.0, 0x30B0C7), (4.6, 7.0, 0xFF375F)] {
            color(hex).setStroke()
            let line = NSBezierPath()
            line.lineWidth = 1.6 * s
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: art.minX + 5.5 * s, y: art.minY + y * s))
            line.line(to: NSPoint(x: art.minX + (5.5 + width - 1.6) * s, y: art.minY + y * s))
            line.stroke()
        }

        // Clip at the top, gold, with a hole.
        let clip = NSBezierPath(roundedRect: r(5.6, 12.4, 6.8, 4.6), xRadius: 1.5 * s, yRadius: 1.5 * s)
        NSGradient(starting: color(0xFFD65A), ending: color(0xF2A900))?.draw(in: clip, angle: -90)
        color(0xB77900).withAlphaComponent(0.7).setStroke()
        clip.lineWidth = 0.6 * s
        clip.stroke()
        color(0x2D5BE3).setFill()
        NSBezierPath(ovalIn: r(7.9, 14.1, 2.2, 1.6)).fill()
    }
}
