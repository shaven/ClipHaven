import Foundation

/// What the hover preview shows for a clip or snippet. Bytes are passed through; the app draws them.
public enum PreviewContent: Equatable, Sendable {
    /// The first part of the text, already cut to `ClipPreview.textLimit` characters.
    case text(String)
    case image(Data)
    case pdf(Data)
    /// RTF or RTFD with no plain text alongside it; the app flattens it.
    case rich(Data, isRTFD: Bool)
    /// A Filenames clip: the file paths.
    case files([String])
    /// A locked snippet: a description, never the value.
    case locked(String)
}

public enum ClipPreview {
    public static let textLimit = 300
    static let lineLimit = 10

    /// Picks the most useful representation of a clip: files, then text, then a picture, PDF or rich text.
    public static func content(for representations: [Representation]) -> PreviewContent? {
        func rep(_ types: [String]) -> Representation? {
            for type in types { if let found = representations.first(where: { $0.type == type }) { return found } }
            return nil
        }
        if let urls = ClipAction.fileURLs(of: representations) {
            return .files(urls.prefix(8).map { $0.isFileURL ? $0.path : $0.absoluteString })
        }
        if let text = rep([ClipType.string.pasteboardType, ClipType.url.pasteboardType]) {
            return .text(excerpt(text.data))
        }
        let imageTypes = [ClipType.png, .tiff, .pict].map(\.pasteboardType) + ["public.jpeg", "public.heic"]
        if let image = rep(imageTypes) { return .image(image.data) }
        if let pdf = rep([ClipType.pdf.pasteboardType]) { return .pdf(pdf.data) }
        if let rtf = rep([ClipType.rtf.pasteboardType]) { return .rich(rtf.data, isRTFD: false) }
        if let rtfd = rep([ClipType.rtfd.pasteboardType]) { return .rich(rtfd.data, isRTFD: true) }
        return nil
    }

    /// A snippet's preview. A locked one says what it is and never shows its value.
    public static func content(for snippet: Snippet) -> PreviewContent {
        if snippet.secret != nil { return .locked("Keychain password") }
        if snippet.requiresAuth { return .locked("Requires Touch ID") }
        return .text(excerpt(Data(snippet.content.utf8)))
    }

    /// The start of `data` as text: at most `textLimit` characters and `lineLimit` lines, with an
    /// ellipsis when anything was cut. Only a bounded slice of the bytes is decoded.
    public static func excerpt(_ data: Data, limit: Int = textLimit) -> String {
        let slice = data.prefix(limit * 4 + 4)
        var text = String(decoding: slice, as: UTF8.self)
        var cut = slice.count < data.count
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > lineLimit {
            text = lines.prefix(lineLimit).joined(separator: "\n")
            cut = true
        }
        if text.count > limit {
            text = String(text.prefix(limit))
            cut = true
        }
        return cut ? text + "…" : text
    }
}
