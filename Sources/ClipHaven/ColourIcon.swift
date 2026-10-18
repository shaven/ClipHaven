import AppKit

/// ClipHaven's coloured icon, for the menu bar and the app: a blue-framed clipboard with a white
/// sheet, a bold red "CH" and a gold clip. Drawn in code, so it stays sharp at every size.
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
        if forApp {
            drawApp(in: NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * 0.1, dy: side * 0.1))
        } else {
            draw(in: NSRect(x: 0, y: 0, width: side, height: side), margin: 0)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// The app icon: macOS's usual light rounded tile with a slate clipboard and a bold "CH".
    private static func drawApp(in art: NSRect) {
        let w = art.width
        func r(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: art.minX + x * w, y: art.minY + y * w, width: width * w, height: height * w)
        }
        let tile = NSBezierPath(roundedRect: art, xRadius: w * 0.2237, yRadius: w * 0.2237)
        NSGradient(starting: color(0xFFFFFF), ending: color(0xDCE1E8))?.draw(in: tile, angle: -90)
        color(0xC3CAD4).setStroke()
        tile.lineWidth = w * 0.006
        tile.stroke()

        // Clipboard board and sheet.
        let board = NSBezierPath(roundedRect: r(0.22, 0.12, 0.56, 0.68), xRadius: w * 0.06, yRadius: w * 0.06)
        NSGradient(starting: color(0x5A6678), ending: color(0x39424F))?.draw(in: board, angle: -90)
        color(0xFFFFFF).setFill()
        NSBezierPath(roundedRect: r(0.27, 0.17, 0.46, 0.55), xRadius: w * 0.035, yRadius: w * 0.035).fill()

        // Clip.
        let clip = NSBezierPath(roundedRect: r(0.37, 0.72, 0.26, 0.12), xRadius: w * 0.035, yRadius: w * 0.035)
        NSGradient(starting: color(0xB8C0CC), ending: color(0x8993A3))?.draw(in: clip, angle: -90)
        color(0x39424F).setStroke()
        clip.lineWidth = w * 0.008
        clip.stroke()
        color(0x39424F).setFill()
        NSBezierPath(ovalIn: r(0.46, 0.76, 0.08, 0.04)).fill()

        // "CH", one bold line centred on the sheet.
        let text = NSAttributedString(string: "CH", attributes: [
            .font: NSFont.systemFont(ofSize: w * 0.25, weight: .heavy),
            .foregroundColor: color(0x2A6FDB),
            .kern: w * 0.004])
        let size = text.size()
        text.draw(at: NSPoint(x: art.midX - size.width / 2, y: art.minY + w * 0.445 - size.height / 2))
    }

    /// Draws on an 18-point grid fitted into `rect` less `margin` on each side.
    private static func draw(in rect: NSRect, margin: CGFloat) {
        let art = rect.insetBy(dx: margin, dy: margin)
        let s = art.width / 18
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: art.minX + x * s, y: art.minY + y * s, width: w * s, height: h * s)
        }

        // Board: a strong blue frame, so the icon reads at menu-bar size.
        let board = NSBezierPath(roundedRect: r(1.2, 0.2, 15.6, 15.8), xRadius: 3.4 * s, yRadius: 3.4 * s)
        NSGradient(starting: color(0x2F7BFF), ending: color(0x0A3FD1))?.draw(in: board, angle: -90)
        color(0x082C9E).setStroke()
        board.lineWidth = 0.9 * s
        board.stroke()

        // Sheet.
        color(0xFFFFFF).setFill()
        NSBezierPath(roundedRect: r(3.2, 1.7, 11.6, 11.3), xRadius: 1.8 * s, yRadius: 1.8 * s).fill()

        // Upright bold red "C" up and to the left, "H" down and to the right: each sits `step`
        // points off the sheet's centre along the diagonal (as in StatusIcon).
        let font = NSFont.systemFont(ofSize: 7.4 * s, weight: .black)
        let step: CGFloat = 2.4
        for (letter, offset) in [("C", -step), ("H", step)] {
            let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: color(0xE3141F)])
            let size = text.size()
            text.draw(at: NSPoint(x: art.minX + (9 + offset) * s - size.width / 2,
                                  y: art.minY + (6.9 - offset) * s - size.height / 2))
        }

        // Clip at the top, gold, with a hole.
        let clip = NSBezierPath(roundedRect: r(5.6, 12.4, 6.8, 4.6), xRadius: 1.5 * s, yRadius: 1.5 * s)
        NSGradient(starting: color(0xFFD65A), ending: color(0xF2A900))?.draw(in: clip, angle: -90)
        color(0x9A6500).setStroke()
        clip.lineWidth = 0.8 * s
        clip.stroke()
        color(0x0A3FD1).setFill()
        NSBezierPath(ovalIn: r(7.9, 14.1, 2.2, 1.6)).fill()
    }
}
