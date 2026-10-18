import Foundation

public struct ImportedSnippet: Equatable, Sendable {
    public let title: String
    public let content: String
    public let enabled: Bool
    /// Set when the snippet's value lives in the Keychain; `content` is then empty.
    public let secret: SecretRef?
    public let requiresAuth: Bool

    public init(title: String, content: String, enabled: Bool, secret: SecretRef? = nil, requiresAuth: Bool = false) {
        self.title = title
        self.content = content
        self.enabled = enabled
        self.secret = secret
        self.requiresAuth = requiresAuth
    }
}

public struct ImportedFolder: Equatable, Sendable {
    public let title: String
    public let enabled: Bool
    public let snippets: [ImportedSnippet]
    /// Title of the top-level folder this one goes inside; nil for a top-level folder.
    public let parent: String?

    public init(title: String, enabled: Bool, snippets: [ImportedSnippet], parent: String? = nil) {
        self.title = title
        self.enabled = enabled
        self.snippets = snippets
        self.parent = parent
    }
}

public enum ClipMenuImportError: Error, CustomStringConvertible {
    case notAClipMenuStore
    case malformed(String)

    public var description: String {
        switch self {
        case .notAClipMenuStore: "not a ClipMenu Snippets.xml (no <database> root)"
        case .malformed(let reason): "Snippets.xml could not be read: \(reason)"
        }
    }
}

/// Reads ClipMenu's `Snippets.xml`, a Core Data XML store, with a plain XML parser (no Core Data
/// runtime). Entities are `FOLDER` and `SNIPPET`; each has `title`, `index` and `enabled`, a
/// snippet also `content` and a `folder` relationship. Folders and snippets come back in their
/// `index` order. A snippet whose folder is not in the file cannot be placed and is left out,
/// as ClipMenu's menu would leave it out.
public enum ClipMenuImport {
    public static func parse(_ data: Data) throws -> [ImportedFolder] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw ClipMenuImportError.malformed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        guard reader.sawDatabaseRoot else { throw ClipMenuImportError.notAClipMenuStore }
        return reader.result()
    }

    /// Copies `source` into `backupDirectory` (dated, never overwritten), parses it and adds its
    /// folders to `store`. The backup comes first, so a failed import still leaves the original
    /// safe; a file that does not parse changes nothing.
    public static func importFile(at source: URL, into store: SnippetStore, backupDirectory: URL,
                                  date: Date = Date()) throws -> (counts: ImportCounts, backup: URL) {
        let data = try Data(contentsOf: source)
        let folders = try parse(data)

        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        // 19700101T000000Z -> keep the date's dashes for readability.
        let readable = "\(stamp.prefix(4))-\(stamp.dropFirst(4).prefix(2))-\(stamp.dropFirst(6))"
        let backup = backupDirectory.appendingPathComponent("Snippets-\(readable).xml")
        try data.write(to: backup, options: .withoutOverwriting)

        return (try store.importFolders(folders), backup)
    }

    private struct Object {
        var type: String
        var id: String
        var title = ""
        var index = 0
        var enabled = true
        var content = ""
        var folderID: String?
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var sawDatabaseRoot = false
        private var objects: [Object] = []
        private var current: Object?
        private var attribute: String?
        private var text = ""
        private var depth = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes attrs: [String: String]) {
            depth += 1
            switch name {
            case "database" where depth == 1:
                sawDatabaseRoot = true
            case "object":
                current = Object(type: attrs["type"] ?? "", id: attrs["id"] ?? "")
            case "attribute":
                attribute = attrs["name"]
                text = ""
            case "relationship" where attrs["name"] == "folder":
                current?.folderID = attrs["idrefs"]?.split(separator: " ").first.map(String.init)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if attribute != nil { text += string }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if attribute != nil { text += String(decoding: CDATABlock, as: UTF8.self) }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            depth -= 1
            switch name {
            case "attribute":
                guard let attribute, current != nil else { return }
                switch attribute {
                case "title": current?.title = text
                case "content": current?.content = text
                case "index": current?.index = Int(text.trimmingCharacters(in: .whitespaces)) ?? 0
                case "enabled": current?.enabled = text.trimmingCharacters(in: .whitespaces) != "0"
                default: break
                }
                self.attribute = nil
            case "object":
                if let current { objects.append(current) }
                current = nil
            default:
                break
            }
        }

        func result() -> [ImportedFolder] {
            let folders = objects.filter { $0.type == "FOLDER" }.enumerated().sorted { ($0.element.index, $0.offset) < ($1.element.index, $1.offset) }
            let snippets = objects.filter { $0.type == "SNIPPET" }.enumerated().sorted { ($0.element.index, $0.offset) < ($1.element.index, $1.offset) }
            return folders.map { _, folder in
                ImportedFolder(
                    title: folder.title,
                    enabled: folder.enabled,
                    snippets: snippets.map(\.element).filter { $0.folderID == folder.id }.map {
                        ImportedSnippet(title: $0.title, content: $0.content, enabled: $0.enabled)
                    })
            }
        }
    }
}
