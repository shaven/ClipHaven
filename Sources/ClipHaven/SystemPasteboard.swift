import AppKit
import ClipHavenCore

/// The general pasteboard, seen through `PasteboardSource`.
final class SystemPasteboard: PasteboardSource {
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
}
