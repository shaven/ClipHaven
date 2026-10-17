import AppKit

/// The status-bar icon: an outlined clipboard with ClipMenu's clip on top and "CH" on the board.
/// Drawn as a template image so macOS tints it for light and dark menu bars.
enum StatusIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(scale: rect.width / 18)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ClipHaven"
        return image
    }

    /// Draws on an 18-point grid scaled by `s`.
    static func draw(scale s: CGFloat, letterSize: CGFloat = 6.8, step: CGFloat = 2.2) {
        NSColor.black.set()

        // Board outline.
        let board = NSBezierPath(roundedRect: NSRect(x: 3.2 * s, y: 1.2 * s, width: 11.6 * s, height: 13.1 * s),
                                 xRadius: 1.4 * s, yRadius: 1.4 * s)
        board.lineWidth = 1.4 * s
        board.stroke()

        // Clip: a tab across the top edge of the board, with a hole in it.
        NSBezierPath(roundedRect: NSRect(x: 5.5 * s, y: 12.8 * s, width: 7 * s, height: 3 * s),
                     xRadius: 1 * s, yRadius: 1 * s).fill()
        NSBezierPath(roundedRect: NSRect(x: 7 * s, y: 15 * s, width: 4 * s, height: 2.5 * s),
                     xRadius: 1.2 * s, yRadius: 1.2 * s).fill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: NSRect(x: 8.25 * s, y: 15.6 * s, width: 1.5 * s, height: 1.2 * s)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        // Upright "C" up and to the left, "H" down and to the right: each sits `step`
        // points off the board's centre along the diagonal.
        let font = NSFont.systemFont(ofSize: letterSize * s, weight: .heavy)
        for (letter, offset) in [("C", -step), ("H", step)] {
            let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: NSColor.black])
            let size = text.size()
            text.draw(at: NSPoint(x: (9 + offset) * s - size.width / 2, y: (7.2 - offset) * s - size.height / 2))
        }
    }
}
