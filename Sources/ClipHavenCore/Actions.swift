import AppKit

/// ClipMenu's two built-in actions, offered on Control-click. Its JavaScript actions are out of
/// scope until they are listed.
public enum ClipAction: String, CaseIterable, Sendable {
    case pasteAsPlainText
    case remove

    public var title: String {
        switch self {
        case .pasteAsPlainText: "Paste as Plain Text"
        case .remove: "Remove"
        }
    }

    /// The actions that make sense for a clip: plain text only when it has text to give.
    public static func available(for representations: [Representation]) -> [ClipAction] {
        allCases.filter { $0 != .pasteAsPlainText || plainText(of: representations) != nil }
    }

    /// The clip reduced to one plain-text representation, or nil when it has no text. RTF and
    /// RTFD are flattened when there is no plain string alongside them.
    public static func plainText(of representations: [Representation]) -> [Representation]? {
        let stringType = ClipType.string.pasteboardType
        if let plain = representations.first(where: { $0.type == stringType }) { return [plain] }

        let text: String? = representations.lazy.compactMap { rep -> String? in
            switch rep.type {
            case ClipType.rtf.pasteboardType: NSAttributedString(rtf: rep.data, documentAttributes: nil)?.string
            case ClipType.rtfd.pasteboardType: NSAttributedString(rtfd: rep.data, documentAttributes: nil)?.string
            case ClipType.url.pasteboardType: String(data: rep.data, encoding: .utf8)
            default: nil
            }
        }.first
        guard let text else { return nil }
        return [Representation(type: stringType, data: Data(text.utf8))]
    }
}
