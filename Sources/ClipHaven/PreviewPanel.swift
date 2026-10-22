import AppKit
import ClipHavenCore
import ImageIO
import UniformTypeIdentifiers

/// The small floating card beside the menu that shows what a highlighted clip or snippet holds.
/// It never takes focus or mouse events, so the menu and the app being pasted into are undisturbed.
@MainActor
final class PreviewPanel {
    private static let maxImageSide: CGFloat = 220
    private static let textWidth: CGFloat = 300

    private let panel: NSPanel
    private let stack = NSStackView()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
    }

    func hide() {
        panel.orderOut(nil)
    }

    func show(_ content: PreviewContent) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch content {
        case .text(let text):
            add(text: text, font: .systemFont(ofSize: 12))
        case .locked(let note):
            add(text: note, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        case .image(let data):
            guard let picture = Self.thumbnail(from: data) else { return hide() }
            add(image: picture.image)
            add(text: "\(Int(picture.pixels.width)) × \(Int(picture.pixels.height))", font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
        case .pdf(let data):
            guard let page = Self.pdfFirstPage(data) else { return hide() }
            add(image: page)
            add(text: "PDF", font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
        case .rich(let data, let isRTFD):
            let attributed = try? NSAttributedString(data: data, options: [.documentType: isRTFD ? NSAttributedString.DocumentType.rtfd : .rtf],
                                                     documentAttributes: nil)
            add(text: ClipPreview.excerpt(Data((attributed?.string ?? "").utf8)), font: .systemFont(ofSize: 12))
        case .files(let paths):
            if let first = paths.first, let picture = Self.fileThumbnail(path: first) { add(image: picture) }
            add(text: paths.joined(separator: "\n"), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        }
        guard !stack.arrangedSubviews.isEmpty else { return hide() }
        panel.setContentSize(stack.fittingSize)
        position()
        panel.orderFrontRegardless()
    }

    // MARK: - Building

    private func add(text: String, font: NSFont, color: NSColor = .labelColor) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = 12
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = Self.textWidth
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        label.widthAnchor.constraint(lessThanOrEqualToConstant: Self.textWidth).isActive = true
        stack.addArrangedSubview(label)
    }

    private func add(image: NSImage) {
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.widthAnchor.constraint(equalToConstant: image.size.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: image.size.height).isActive = true
        stack.addArrangedSubview(view)
    }

    // MARK: - Pictures

    /// A reduced copy made by ImageIO, so a 10 MB screenshot is never drawn at full size.
    private static func thumbnail(from data: Data) -> (image: NSImage, pixels: CGSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixels = CGSize(width: properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0,
                            height: properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxImageSide * 2]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let scale = min(1, maxImageSide / CGFloat(max(cg.width, cg.height) / 2))
        let size = NSSize(width: CGFloat(cg.width) / 2 * scale, height: CGFloat(cg.height) / 2 * scale)
        return (NSImage(cgImage: cg, size: size), pixels)
    }

    private static func pdfFirstPage(_ data: Data) -> NSImage? {
        guard let rep = NSPDFImageRep(data: data) else { return nil }
        let scale = min(1, maxImageSide / max(rep.bounds.width, rep.bounds.height))
        let size = NSSize(width: rep.bounds.width * scale, height: rep.bounds.height * scale)
        let page = NSImage(size: size)
        page.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size))
        page.unlockFocus()
        return page
    }

    /// A picture of the file when it is an image; nil for anything else.
    private static func fileThumbnail(path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .image),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return thumbnail(from: data)?.image
    }

    // MARK: - Placement

    /// Beside the menu the pointer is in: right of it, or left when the screen edge is in the way.
    /// Level with the pointer when it is over the menu, else at the menu's top (keyboard navigation).
    private func position() {
        let mouse = NSEvent.mouseLocation
        let menus = NSApp.windows.filter { $0 !== panel && $0.isVisible && String(describing: type(of: $0)).contains("Menu") }
        let menu = menus.first { $0.frame.contains(mouse) } ?? menus.max { $0.frame.maxX < $1.frame.maxX }
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? .zero

        var x = (menu?.frame.maxX ?? mouse.x + 20) + 4
        if x + size.width > bounds.maxX { x = (menu?.frame.minX ?? mouse.x - 20) - size.width - 4 }
        let anchorY = menu.map { $0.frame.contains(mouse) ? mouse.y + 8 : $0.frame.maxY } ?? mouse.y + 8
        let y = max(bounds.minY, min(anchorY - size.height, bounds.maxY - size.height))
        panel.setFrameOrigin(NSPoint(x: max(bounds.minX, x), y: y))
    }
}
