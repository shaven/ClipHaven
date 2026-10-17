import AppKit
import ClipHavenCore

/// The general pasteboard, seen through `PasteboardSource` and `PasteboardWriter`.
final class SystemPasteboard: PasteboardSource, SecretPasteboard {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var itemTypes: [[String]] {
        (pasteboard.pasteboardItems ?? []).map { $0.types.map(\.rawValue) }
    }

    func data(forType type: String, item: Int) -> Data? {
        guard let items = pasteboard.pasteboardItems, items.indices.contains(item) else { return nil }
        return items[item].data(forType: NSPasteboard.PasteboardType(type))
    }

    /// One pasteboard item holds every type; a multi-file clip (stored one URL per line) gets
    /// one extra item per further file, as Finder writes them.
    func write(_ representations: [Representation]) {
        let first = NSPasteboardItem()
        var items = [first]
        for rep in representations {
            guard rep.type == ClipType.filenames.pasteboardType else {
                first.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type))
                continue
            }
            let urls = String(decoding: rep.data, as: UTF8.self).split(separator: "\n")
            for (i, url) in urls.enumerated() {
                let item = i == 0 ? first : NSPasteboardItem()
                item.setString(String(url), forType: .fileURL)
                if i > 0 { items.append(item) }
            }
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    /// The first item's types and data, to put back after a secret paste. A multi-item clip
    /// comes back as its first item only.
    func snapshot() -> [Representation] {
        guard let item = pasteboard.pasteboardItems?.first else { return [] }
        return item.types.compactMap { type in
            item.data(forType: type).map { Representation(type: type.rawValue, data: $0) }
        }
    }

    func clear() {
        pasteboard.clearContents()
    }
}
