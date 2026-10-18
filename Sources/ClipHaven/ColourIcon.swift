import AppKit

/// ClipHaven's icon, used for the menu bar and the app: the original outlined clipboard with its
/// clip on top, a bold red "CH" at the top of the board and a few lines of text below it. Drawn
/// in code, so it stays sharp at every size.
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

    /// A square PNG of `pixels`. The app icon sits on macOS's usual light rounded tile, with a
    /// margin around it; the plain one is the mark alone.
    static func png(pixels: Int, forApp: Bool) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let side = CGFloat(pixels)
        let full = NSRect(x: 0, y: 0, width: side, height: side)
        if forApp {
            let art = full.insetBy(dx: side * 0.1, dy: side * 0.1)
            let tile = NSBezierPath(roundedRect: art, xRadius: art.width * 0.2237, yRadius: art.width * 0.2237)
            NSGradient(starting: .white, ending: NSColor(srgbRed: 0.86, green: 0.88, blue: 0.91, alpha: 1))?.draw(in: tile, angle: -90)
            NSColor(srgbRed: 0.76, green: 0.79, blue: 0.83, alpha: 1).setStroke()
            tile.lineWidth = art.width * 0.006
            tile.stroke()
            drawMark(in: art.insetBy(dx: art.width * 0.17, dy: art.width * 0.17), ink: NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1))
        } else {
            drawMark(in: full, ink: .black)
        }
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
