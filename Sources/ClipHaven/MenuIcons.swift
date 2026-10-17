import AppKit
import ClipHavenCore
import UniformTypeIdentifiers

/// Draws the menu's icons: Finder's own icons for the clip types and folders, as ClipMenu
/// does, small colour symbols for snippets and scripts, and a thumbnail for an image clip.
@MainActor
final class MenuIcons {
    var appearance = MenuAppearance() {
        didSet {
            if oldValue.iconSize != appearance.iconSize { icons.removeAll(); fileIcons.removeAll() }
            if oldValue.thumbnailSize != appearance.thumbnailSize { thumbnails.removeAll() }
        }
    }
    private var icons: [String: NSImage] = [:]
    private var thumbnails: [Int64: NSImage] = [:]
    private var fileIcons: [Int64: NSImage] = [:]

    func image(_ kind: MenuIconKind) -> NSImage? {
        let key = "\(kind)"
        if let cached = icons[key] { return cached }
        guard let image = make(kind) else { return nil }
        icons[key] = image
        return image
    }

    private func make(_ kind: MenuIconKind) -> NSImage? {
        guard let name = kind.symbol else { return finder(.folder) }
        return symbol(name, Self.colour(kind.tint))
    }

    private static func colour(_ tint: MenuIconTint) -> NSColor {
        switch tint {
        case .blue: .systemBlue
        case .orange: .systemOrange
        case .red: .systemRed
        case .teal: .systemTeal
        case .green: .systemGreen
        case .gray: .systemGray
        case .indigo: .systemIndigo
        case .yellow: .systemYellow
        case .purple: .systemPurple
        }
    }

    private var side: CGFloat { CGFloat(appearance.iconSize) }

    private func finder(_ type: UTType) -> NSImage {
        let icon = (NSWorkspace.shared.icon(for: type).copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: side, height: side)
        return icon
    }

    /// A coloured symbol centred on a square canvas, so titles line up with the Finder icons.
    private func symbol(_ name: String, _ colour: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.72, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colour, colour.withAlphaComponent(0.55)]))
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let size = glyph.size
            glyph.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2,
                                  width: size.width, height: size.height))
            return true
        }
    }

    /// The real Finder icon of the first file in a Filenames clip, or nil if there is none.
    func fileIcon(for id: Int64, in store: HistoryStore) -> NSImage? {
        if let cached = fileIcons[id] { return cached }
        guard let clip = try? store.clip(id: id), let url = ClipAction.fileURLs(of: clip.representations)?.first else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage
        icon?.size = NSSize(width: side, height: side)
        if fileIcons.count > 200 { fileIcons.removeAll() }
        fileIcons[id] = icon
        return icon
    }

    /// A picture of an image clip that fits the thumbnail box, or nil if it cannot be read.
    func thumbnail(for id: Int64, in store: HistoryStore) -> NSImage? {
        if let cached = thumbnails[id] { return cached }
        let imageTypes = [ClipType.tiff, .png, .pict].map(\.pasteboardType)
        guard let clip = try? store.clip(id: id),
              let rep = clip.representations.first(where: { imageTypes.contains($0.type) }),
              let source = NSImage(data: rep.data) else { return nil }
        let size = Thumbnail.size(for: source.size, within: appearance.thumbnailSize)
        guard size != .zero else { return nil }

        // Drawn once into a small bitmap, so the cache does not hold the full-size picture.
        let small = NSImage(size: size)
        small.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        small.unlockFocus()
        if thumbnails.count > 200 { thumbnails.removeAll() }
        thumbnails[id] = small
        return small
    }
}
