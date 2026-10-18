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
    enum Style { case mark, tile, layer }

    static func png(pixels: Int, style: Style) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let side = CGFloat(pixels)
        let full = NSRect(x: 0, y: 0, width: side, height: side)
        switch style {
        case .mark:
            drawMark(in: full, ink: .black)
        case .layer:
            // Artwork only, on a transparent square; the system supplies the tile and its gloss.
            drawRich(in: full.insetBy(dx: side * 0.13, dy: side * 0.1))
        case .tile:
            // For the plain `.icns`, which older macOS shows as it is: the tile and the artwork.
            let art = full.insetBy(dx: side * 0.0977, dy: side * 0.0977)
            let tile = NSBezierPath(roundedRect: art, xRadius: art.width * 0.2237, yRadius: art.width * 0.2237)
            NSGradient(starting: .white, ending: NSColor(srgbRed: 0.84, green: 0.85, blue: 0.87, alpha: 1))?.draw(in: tile, angle: -90)
            drawRich(in: art.insetBy(dx: art.width * 0.15, dy: art.width * 0.1))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// The full-size artwork, coloured like ClipMenu's clipboard: a dark brown board, white paper
    /// and a silver clip, with a bold red "CH" at the top of the paper and text lines below it.
    /// `rect` is the area it fills.
    private static func drawRich(in rect: NSRect) {
        let w = rect.width, h = rect.height
        func r(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: rect.minX + x * w, y: rect.minY + y * h, width: width * w, height: height * h)
        }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = w * 0.035
        shadow.shadowOffset = NSSize(width: 0, height: -w * 0.02)

        // Board.
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        let board = NSBezierPath(roundedRect: r(0, 0, 1, 0.9), xRadius: w * 0.09, yRadius: w * 0.09)
        NSGradient(starting: hex(0x6A4A33), ending: hex(0x35241A))?.draw(in: board, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Paper.
        let paper = NSBezierPath(roundedRect: r(0.09, 0.07, 0.82, 0.69), xRadius: w * 0.04, yRadius: w * 0.04)
        NSGradient(starting: .white, ending: hex(0xE4E4E6))?.draw(in: paper, angle: -90)

        // "CH" across the top of the paper.
        let text = NSAttributedString(string: "CH", attributes: [
            .font: NSFont.systemFont(ofSize: w * 0.46, weight: .black),
            .foregroundColor: hex(0xE3141F),
            .kern: w * 0.008])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.minY + h * 0.50 - size.height / 2 + h * 0.02))

        // Text lines, moved down.
        hex(0x3B3F46).setFill()
        for (y, width) in [(0.27, 0.62), (0.185, 0.62), (0.10, 0.40)] as [(CGFloat, CGFloat)] {
            NSBezierPath(roundedRect: r(0.19, y, width, 0.045), xRadius: w * 0.02, yRadius: w * 0.02).fill()
        }

        // Clip.
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        let clip = NSBezierPath(roundedRect: r(0.30, 0.82, 0.40, 0.18), xRadius: w * 0.05, yRadius: w * 0.05)
        NSGradient(starting: hex(0xF1F2F4), ending: hex(0x9298A3))?.draw(in: clip, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        hex(0x5C626D).setStroke()
        clip.lineWidth = w * 0.008
        clip.stroke()
        hex(0x35241A).setFill()
        NSBezierPath(ovalIn: r(0.44, 0.905, 0.12, 0.055)).fill()
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
