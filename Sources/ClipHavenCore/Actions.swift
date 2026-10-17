import AppKit

/// ClipMenu's four built-in actions, offered on Control-click. Its JavaScript actions are
/// `ActionNode.Kind.script`, run by `ActionService`.
public enum ClipAction: String, CaseIterable, Sendable, Codable {
    case pasteAsPlainText
    case remove
    case pasteAsFilePath
    case pasteAsHFSFilePath

    /// The name ClipMenu's `actions.plist` uses, e.g. `pasteAsPlainText:`.
    public init?(clipMenuName: String) {
        guard let match = Self.allCases.first(where: { $0.rawValue + ":" == clipMenuName }) else { return nil }
        self = match
    }

    public var title: String {
        switch self {
        case .pasteAsPlainText: "Paste as Plain Text"
        case .remove: "Remove"
        case .pasteAsFilePath: "Paste as File Path"
        case .pasteAsHFSFilePath: "Paste as HFS File Path"
        }
    }

    /// The actions that make sense for a clip: plain text only when it has text to give.
    public static func available(for representations: [Representation]) -> [ClipAction] {
        allCases.filter { action in
            switch action {
            case .pasteAsPlainText: plainText(of: representations) != nil
            case .remove: true
            case .pasteAsFilePath, .pasteAsHFSFilePath: fileURLs(of: representations) != nil
            }
        }
    }

    /// The files of a Filenames clip (stored one URL per line), or nil when it has none.
    public static func fileURLs(of representations: [Representation]) -> [URL]? {
        guard let rep = representations.first(where: { $0.type == ClipType.filenames.pasteboardType }) else { return nil }
        let urls = String(decoding: rep.data, as: UTF8.self).split(separator: "\n").compactMap { URL(string: String($0)) }
        return urls.isEmpty ? nil : urls
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
