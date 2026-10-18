import Foundation

/// Where the snippet snapshot lives. In the app it is one iCloud-synchronizable Keychain item.
public protocol SnapshotStore: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

public struct SyncReport: Equatable, Sendable {
    /// What was taken in from the other Macs.
    public let added: ImportCounts
    /// Snippets now in the shared snapshot.
    public let sent: Int
    /// Snippets left out because they are plain text flagged "Require Touch ID".
    public let skipped: Int
}

public enum SyncError: Error, CustomStringConvertible {
    case unreadable(String)
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .unreadable(let reason): "The shared snippet list could not be read: \(reason)"
        case .unsupportedVersion(let v): "The shared snippet list is version \(v); this build reads version \(SnippetSync.version). Update ClipHaven."
        }
    }
}

/// Shares the snippet list between Macs through one Keychain item. The snapshot holds plain
/// snippets with their text and Keychain snippets as service and account only, never a value.
/// A plain snippet flagged "Require Touch ID" is left out: its text is something the owner
/// marked sensitive, so it should be moved to the Keychain first. Syncing adds what is missing
/// on each side and replaces nothing; a deletion does not travel.
public enum SnippetSync {
    public static let version = 1

    private struct File: Codable {
        var version: Int
        var device: String
        var updated: Date
        var folders: [Folder]
    }

    private struct Folder: Codable {
        /// Title of the top-level folder this one sits in; absent in snapshots from before subfolders.
        var parent: String?
        var title: String
        var enabled: Bool
        var snippets: [Snippet]
    }

    private struct Snippet: Codable {
        var title: String
        var content: String?
        var enabled: Bool
        var requiresAuth: Bool?
        var keychain: Ref?
    }

    private struct Ref: Codable {
        var service: String
        var account: String
    }

    public static func snapshot(of snippets: SnippetStore, device: String, date: Date = Date()) throws -> (data: Data, skipped: Int, count: Int) {
        var skipped = 0, count = 0
        let all = try snippets.folders()
        let titles = Dictionary(all.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let folders = all.map { folder in
            Folder(parent: folder.parentID.flatMap { titles[$0] }, title: folder.title, enabled: folder.enabled, snippets: folder.snippets.compactMap { snippet -> Snippet? in
                if snippet.secret == nil, snippet.requiresAuth { skipped += 1; return nil }
                count += 1
                return Snippet(title: snippet.title,
                               content: snippet.secret == nil ? snippet.content : nil,
                               enabled: snippet.enabled,
                               requiresAuth: snippet.requiresAuth ? true : nil,
                               keychain: snippet.secret.map { Ref(service: $0.service, account: $0.account) })
            })
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try encoder.encode(File(version: version, device: device, updated: date, folders: folders)), skipped, count)
    }

    /// Adds what the snapshot has and the store lacks. A file that does not parse changes nothing.
    @discardableResult
    public static func merge(_ data: Data, into snippets: SnippetStore) throws -> ImportCounts {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: File
        do {
            file = try decoder.decode(File.self, from: data)
        } catch {
            throw SyncError.unreadable("\(error)")
        }
        guard file.version == version else { throw SyncError.unsupportedVersion(file.version) }

        return try snippets.mergeFolders(file.folders.map { folder in
            ImportedFolder(title: folder.title, enabled: folder.enabled, snippets: folder.snippets.compactMap { snippet in
                let secret = snippet.keychain.map { SecretRef(service: $0.service, account: $0.account) }
                // Plain text flagged as sensitive is never taken from a file.
                if secret == nil, snippet.requiresAuth == true { return nil }
                return ImportedSnippet(title: snippet.title, content: secret == nil ? snippet.content ?? "" : "",
                                       enabled: snippet.enabled, secret: secret, requiresAuth: snippet.requiresAuth ?? false)
            }, parent: folder.parent)
        })
    }

    /// Takes in what the other Macs shared, then shares the combined list. A shared snapshot
    /// that cannot be read stops the sync before anything is written.
    public static func sync(_ snippets: SnippetStore, with store: SnapshotStore, device: String) throws -> SyncReport {
        var added = ImportCounts(folders: 0, snippets: 0)
        if let remote = try store.read() { added = try merge(remote, into: snippets) }
        let snapshot = try snapshot(of: snippets, device: device)
        try store.write(snapshot.data)
        return SyncReport(added: added, sent: snapshot.count, skipped: snapshot.skipped)
    }
}
