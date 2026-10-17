import Foundation

public struct ExportCounts: Equatable, Sendable {
    public let clips: Int
    public let folders: Int
    public let snippets: Int
}

public enum ExportError: Error, CustomStringConvertible {
    case unreadable(String)
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .unreadable(let reason): "not a ClipHaven export: \(reason)"
        case .unsupportedVersion(let v): "export version \(v) is not supported (this build reads version \(Export.version))"
        }
    }
}

/// History and snippets as one JSON file. A Keychain snippet is written as its service and account
/// alone; nothing is ever read from the Keychain, so no secret value can reach the file. A plain
/// snippet, including one flagged "Require Touch ID", is exported with its text, as it is stored.
public enum Export {
    public static let version = 1

    private struct File: Codable {
        var version: Int
        var clips: [Clip]
        var folders: [Folder]
    }

    private struct Clip: Codable {
        var title: String
        var created: Date
        var representations: [Rep]
    }

    private struct Rep: Codable {
        var type: String
        var data: Data  // base64 in JSON
    }

    private struct Folder: Codable {
        var title: String
        var enabled: Bool
        var snippets: [Snippet]
    }

    private struct Snippet: Codable {
        var title: String
        var enabled: Bool
        var requiresAuth: Bool
        var content: String?
        var keychain: Keychain?
    }

    private struct Keychain: Codable, Equatable {
        var service: String
        var account: String
    }

    public static func data(history: HistoryStore, snippets: SnippetStore) throws -> Data {
        let clips = try history.fetch(limit: max(try history.count(), 1)).map { clip in
            Clip(title: clip.title, created: clip.created,
                 representations: clip.representations.map { Rep(type: $0.type, data: $0.data) })
        }
        let folders = try snippets.folders().map { folder in
            Folder(title: folder.title, enabled: folder.enabled, snippets: folder.snippets.map { snippet in
                Snippet(title: snippet.title, enabled: snippet.enabled, requiresAuth: snippet.requiresAuth,
                        content: snippet.secret == nil ? snippet.content : nil,
                        keychain: snippet.secret.map { Keychain(service: $0.service, account: $0.account) })
            })
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(File(version: version, clips: clips, folders: folders))
    }

    /// Adds the file's clips (oldest first, so the order survives) and folders to the stores.
    /// The whole file is read before anything is written, so a bad file changes nothing.
    @discardableResult
    public static func restore(_ data: Data, history: HistoryStore, snippets: SnippetStore) throws -> ExportCounts {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: File
        do {
            file = try decoder.decode(File.self, from: data)
        } catch {
            throw ExportError.unreadable("\(error)")
        }
        guard file.version == version else { throw ExportError.unsupportedVersion(file.version) }

        var clipCount = 0
        for clip in file.clips.reversed() {
            let reps = clip.representations.map { Representation(type: $0.type, data: $0.data) }
            if try history.insert(reps, title: clip.title, created: clip.created) != nil { clipCount += 1 }
        }
        let counts = try snippets.importFolders(file.folders.map { folder in
            ImportedFolder(title: folder.title, enabled: folder.enabled, snippets: folder.snippets.map { snippet in
                ImportedSnippet(title: snippet.title, content: snippet.content ?? "", enabled: snippet.enabled,
                                secret: snippet.keychain.map { SecretRef(service: $0.service, account: $0.account) },
                                requiresAuth: snippet.requiresAuth)
            })
        })
        return ExportCounts(clips: clipCount, folders: counts.folders, snippets: counts.snippets)
    }
}
