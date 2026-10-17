import Foundation

/// Puts representations on the pasteboard; `NSPasteboard` in the app, a recorder in tests.
public protocol PasteboardWriter: AnyObject {
    func write(_ representations: [Representation])
}

/// Sends Cmd+V to the frontmost app; a CGEvent poster in the app, a recorder in tests.
public protocol PasteKeyPoster: AnyObject {
    func postPaste()
}

/// What choosing a menu item does, as ClipMenu does it: the clip goes on the clipboard, moves to
/// the top of history, and is pasted into the frontmost app when auto-paste is on.
public final class Paster {
    public var autoPaste: Bool
    private let store: HistoryStore
    private let writer: PasteboardWriter
    private let poster: PasteKeyPoster

    public init(store: HistoryStore, writer: PasteboardWriter, poster: PasteKeyPoster, autoPaste: Bool = true) {
        self.store = store
        self.writer = writer
        self.poster = poster
        self.autoPaste = autoPaste
    }

    public func choose(clipID: Int64) throws {
        guard let clip = try store.clip(id: clipID) else { return }
        try store.moveToTop(id: clipID)
        paste(clip.representations)
    }

    public func perform(_ action: ClipAction, clipID: Int64) throws {
        switch action {
        case .remove:
            try store.delete(id: clipID)
        case .pasteAsPlainText:
            guard let clip = try store.clip(id: clipID), let plain = ClipAction.plainText(of: clip.representations) else { return }
            paste(plain)
        }
    }

    /// Writes `representations`, marked as ClipHaven's own so the monitor skips them, then
    /// pastes if auto-paste is on.
    public func paste(_ representations: [Representation]) {
        guard !representations.isEmpty else { return }
        writer.write(representations + [Representation(type: ClipboardMonitor.ownMarkerType, data: Data())])
        if autoPaste { poster.postPaste() }
    }
}
