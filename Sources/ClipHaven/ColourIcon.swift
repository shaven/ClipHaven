import AppKit

/// ClipHaven's small icon, for the menu bar: the outlined clipboard with its clip on top, a bold red
/// "CH" at the top of the board and a few lines of text below it. Drawn in code, so it stays sharp.
/// The large app icon is ClipMenu's own artwork with the "CH" added (Resources/AppIcon.icon).
enum ColourIcon {
    private static let red = NSColor(srgbRed: 0xE3 / 255, green: 0x14 / 255, blue: 0x1F / 255, alpha: 1)

    /// For the menu bar. Not a template image, so the red stays red; the outline follows the
    /// menu bar's light or dark appearance each time it is drawn.
    static func menuBar(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawMark(in: rect, ink: .labelColor)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "ClipHaven"
        return image
    }

    /// A square PNG of `pixels` of the small mark, for previews.
    static func png(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawMark(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), ink: .black)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Draws on an 18-point grid fitted into `rect`.
    private static func drawMark(in rect: NSRect, ink: NSColor) {
        let s = rect.width / 18
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: rect.minX + x * s, y: rect.minY + y * s, width: w * s, height: h * s)
        }

        // Board outline.
        ink.setStroke()
        let board = NSBezierPath(roundedRect: r(2.6, 0.9, 12.8, 14.2), xRadius: 1.6 * s, yRadius: 1.6 * s)
        board.lineWidth = 1.5 * s
        board.stroke()

        // Clip: a tab across the top edge of the board, with a hole in it.
        ink.setFill()
        NSBezierPath(roundedRect: r(5.5, 13.1, 7, 3), xRadius: 1 * s, yRadius: 1 * s).fill()
        NSBezierPath(roundedRect: r(7, 15.2, 4, 2.4), xRadius: 1.2 * s, yRadius: 1.2 * s).fill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: r(8.25, 15.75, 1.5, 1.1)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        // "CH" in bold red across the top of the board.
        let text = NSAttributedString(string: "CH", attributes: [
            .font: NSFont.systemFont(ofSize: 6.4 * s, weight: .black),
            .foregroundColor: red,
            .kern: 0.2 * s])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.minX + 9 * s - size.width / 2, y: rect.minY + 9.6 * s - size.height / 2))

        // The rest of the board: lines of text, moved down.
        ink.setFill()
        for (y, width) in [(5.4, 8.0), (3.6, 8.0), (1.8, 5.0)] as [(CGFloat, CGFloat)] {
            NSBezierPath(roundedRect: r(5, y, width, 1.0), xRadius: 0.5 * s, yRadius: 0.5 * s).fill()
        }
    }
}
