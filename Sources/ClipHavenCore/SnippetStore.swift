import Foundation

public struct Snippet: Equatable, Sendable {
    public let id: Int64
    public let title: String
    /// Empty for a Keychain snippet: its value lives only in the Keychain.
    public let content: String
    public let enabled: Bool
    public let secret: SecretRef?
    public let requiresAuth: Bool

    public var isLocked: Bool { secret != nil || requiresAuth }
}

public struct SnippetFolder: Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let enabled: Bool
    public let snippets: [Snippet]
}

public struct ImportCounts: Equatable, Sendable {
    public let folders: Int
    public let snippets: Int
}

/// Snippet folders and snippets, in the same SQLite file as history but on their own connection.
/// Order is an explicit `position`, so reordering rewrites only the rows that moved.
public final class SnippetStore {
    private typealias Value = SQLiteDatabase.Value
    private let database: SQLiteDatabase

    public init(url: URL) throws {
        database = try SQLiteDatabase(url: url)
        try database.exec("""
            CREATE TABLE IF NOT EXISTS snippet_folders (
                id       INTEGER PRIMARY KEY,
                title    TEXT    NOT NULL,
                enabled  INTEGER NOT NULL DEFAULT 1,
                position INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS snippets (
                id        INTEGER PRIMARY KEY,
                folder_id INTEGER NOT NULL REFERENCES snippet_folders (id) ON DELETE CASCADE,
                title     TEXT    NOT NULL,
                content   TEXT    NOT NULL,
                enabled   INTEGER NOT NULL DEFAULT 1,
                position  INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS snippets_folder ON snippets (folder_id, position);
            """)
        try addMissingColumns()
    }

    /// Phase 6 columns, added to a Phase 5 file in place. A Keychain snippet keeps only the
    /// service and account here.
    private func addMissingColumns() throws {
        let existing = Set(try database.query("PRAGMA table_info(snippets)", []) { SQLiteDatabase.text($0, 1) })
        for (name, definition) in [("secret_service", "TEXT"), ("secret_account", "TEXT"),
                                   ("requires_auth", "INTEGER NOT NULL DEFAULT 0")] where !existing.contains(name) {
            try database.exec("ALTER TABLE snippets ADD COLUMN \(name) \(definition)")
        }
    }

    // MARK: - Writing

    @discardableResult
    public func addFolder(title: String, enabled: Bool = true) throws -> Int64 {
        try database.transaction { try insertFolder(title: title, enabled: enabled) }
    }

    @discardableResult
    public func addSnippet(folderID: Int64, title: String, content: String, enabled: Bool = true) throws -> Int64 {
        try database.transaction { try insertSnippet(folderID: folderID, title: title, content: content, enabled: enabled) }
    }

    public func updateFolder(id: Int64, title: String, enabled: Bool) throws {
        try database.run("UPDATE snippet_folders SET title = ?, enabled = ? WHERE id = ?",
                         [.text(title), .int(enabled ? 1 : 0), .int(id)])
    }

    public func updateSnippet(id: Int64, title: String, content: String, enabled: Bool) throws {
        try database.run("UPDATE snippets SET title = ?, content = ?, enabled = ? WHERE id = ?",
                         [.text(title), .text(content), .int(enabled ? 1 : 0), .int(id)])
    }

    /// Makes the snippet a Keychain snippet and drops any plain-text content, in one statement.
    public func setSecret(id: Int64, _ ref: SecretRef) throws {
        try database.run("UPDATE snippets SET secret_service = ?, secret_account = ?, content = '' WHERE id = ?",
                         [.text(ref.service), .text(ref.account), .int(id)])
    }

    public func setRequiresAuth(id: Int64, _ required: Bool) throws {
        try database.run("UPDATE snippets SET requires_auth = ? WHERE id = ?", [.int(required ? 1 : 0), .int(id)])
    }

    public func deleteFolder(id: Int64) throws {
        try database.run("DELETE FROM snippet_folders WHERE id = ?", [.int(id)])
    }

    public func deleteSnippet(id: Int64) throws {
        try database.run("DELETE FROM snippets WHERE id = ?", [.int(id)])
    }

    /// Puts the folders in the given order; ids not listed keep their place after the listed ones.
    public func reorderFolders(_ ids: [Int64]) throws {
        try database.transaction {
            for (position, id) in ids.enumerated() {
                try database.run("UPDATE snippet_folders SET position = ? WHERE id = ?", [.int(Int64(position)), .int(id)])
            }
        }
    }

    public func reorderSnippets(_ ids: [Int64], in folderID: Int64) throws {
        try database.transaction {
            for (position, id) in ids.enumerated() {
                try database.run("UPDATE snippets SET position = ? WHERE id = ? AND folder_id = ?",
                                 [.int(Int64(position)), .int(id), .int(folderID)])
            }
        }
    }

    /// Adds imported folders after the existing ones, all or nothing.
    @discardableResult
    public func importFolders(_ folders: [ImportedFolder]) throws -> ImportCounts {
        try database.transaction {
            var snippetCount = 0
            for folder in folders {
                let id = try insertFolder(title: folder.title, enabled: folder.enabled)
                for snippet in folder.snippets {
                    let snippetID = try insertSnippet(folderID: id, title: snippet.title, content: snippet.content, enabled: snippet.enabled)
                    if let secret = snippet.secret { try setSecret(id: snippetID, secret) }
                    if snippet.requiresAuth { try setRequiresAuth(id: snippetID, true) }
                    snippetCount += 1
                }
            }
            return ImportCounts(folders: folders.count, snippets: snippetCount)
        }
    }

    /// Adds what is missing, all or nothing, and replaces nothing. A folder is matched by title;
    /// a snippet by its title and its text (a Keychain snippet by its title and item). Counts are
    /// of what was added.
    @discardableResult
    public func mergeFolders(_ folders: [ImportedFolder]) throws -> ImportCounts {
        try database.transaction {
            let existing = try self.folders()
            var folderCount = 0, snippetCount = 0
            func key(_ title: String, _ secret: SecretRef?, _ content: String) -> String {
                secret.map { "\(title)\u{0}keychain\u{0}\($0.service)\u{0}\($0.account)" } ?? "\(title)\u{0}text\u{0}\(content)"
            }
            var created: [String: Int64] = [:]
            for folder in folders {
                let match = existing.first { $0.title == folder.title }
                let id: Int64
                var known: Set<String>
                if let match {
                    id = match.id
                    known = Set(match.snippets.map { key($0.title, $0.secret, $0.content) })
                } else if let earlier = created[folder.title] {
                    id = earlier
                    known = []
                } else {
                    id = try insertFolder(title: folder.title, enabled: folder.enabled)
                    created[folder.title] = id
                    folderCount += 1
                    known = []
                }
                for snippet in folder.snippets where known.insert(key(snippet.title, snippet.secret, snippet.content)).inserted {
                    let snippetID = try insertSnippet(folderID: id, title: snippet.title, content: snippet.content, enabled: snippet.enabled)
                    if let secret = snippet.secret { try setSecret(id: snippetID, secret) }
                    if snippet.requiresAuth { try setRequiresAuth(id: snippetID, true) }
                    snippetCount += 1
                }
            }
            return ImportCounts(folders: folderCount, snippets: snippetCount)
        }
    }

    // MARK: - Reading

    /// Every folder with its snippets, in order, enabled or not (the editor shows all).
    public func folders() throws -> [SnippetFolder] {
        let folders = try database.query("SELECT id, title, enabled FROM snippet_folders ORDER BY position, id", []) {
            (SQLiteDatabase.int($0, 0), SQLiteDatabase.text($0, 1), SQLiteDatabase.int($0, 2) != 0)
        }
        return try folders.map { id, title, enabled in
            SnippetFolder(id: id, title: title, enabled: enabled, snippets: try snippets(in: id))
        }
    }

    /// What the menu shows: enabled folders holding their enabled snippets, titles only.
    public func menuSummaries() throws -> [SnippetFolderSummary] {
        try folders().filter(\.enabled).map { folder in
            SnippetFolderSummary(title: folder.title,
                                 snippets: folder.snippets.filter(\.enabled).map { SnippetSummary(id: $0.id, title: $0.title, isLocked: $0.isLocked) })
        }
    }

    public func snippet(id: Int64) throws -> Snippet? {
        try database.query("\(Self.snippetColumns) FROM snippets WHERE id = ?", [.int(id)], row: Self.snippet(from:)).first
    }

    /// How many snippets point at this Keychain item.
    public func secretReferenceCount(_ ref: SecretRef) throws -> Int {
        try database.query("SELECT count(*) FROM snippets WHERE secret_service = ? AND secret_account = ?",
                           [.text(ref.service), .text(ref.account)]) { SQLiteDatabase.int($0, 0) }.first.map(Int.init) ?? 0
    }

    public func folderCount() throws -> Int {
        try database.scalarInt("SELECT count(*) FROM snippet_folders")
    }

    func snippetCount() throws -> Int {
        try database.scalarInt("SELECT count(*) FROM snippets")
    }

    // MARK: - Plumbing

    private static let snippetColumns = "SELECT id, title, content, enabled, secret_service, secret_account, requires_auth"

    private static func snippet(from stmt: OpaquePointer) -> Snippet {
        let service = SQLiteDatabase.text(stmt, 4)
        let account = SQLiteDatabase.text(stmt, 5)
        return Snippet(id: SQLiteDatabase.int(stmt, 0), title: SQLiteDatabase.text(stmt, 1),
                       content: SQLiteDatabase.text(stmt, 2), enabled: SQLiteDatabase.int(stmt, 3) != 0,
                       secret: service.isEmpty ? nil : SecretRef(service: service, account: account),
                       requiresAuth: SQLiteDatabase.int(stmt, 6) != 0)
    }

    private func snippets(in folderID: Int64) throws -> [Snippet] {
        try database.query("\(Self.snippetColumns) FROM snippets WHERE folder_id = ? ORDER BY position, id", [.int(folderID)], row: Self.snippet(from:))
    }

    private func insertFolder(title: String, enabled: Bool) throws -> Int64 {
        let position = try database.scalarInt("SELECT coalesce(max(position), -1) + 1 FROM snippet_folders")
        try database.run("INSERT INTO snippet_folders (title, enabled, position) VALUES (?, ?, ?)",
                         [.text(title), .int(enabled ? 1 : 0), .int(Int64(position))])
        return database.lastInsertRowID
    }

    @discardableResult
    private func insertSnippet(folderID: Int64, title: String, content: String, enabled: Bool) throws -> Int64 {
        let rows = try database.query("SELECT coalesce(max(position), -1) + 1 FROM snippets WHERE folder_id = ?", [.int(folderID)]) {
            SQLiteDatabase.int($0, 0)
        }
        try database.run("INSERT INTO snippets (folder_id, title, content, enabled, position) VALUES (?, ?, ?, ?, ?)",
                         [.int(folderID), .text(title), .text(content), .int(enabled ? 1 : 0), .int(rows.first ?? 0)])
        return database.lastInsertRowID
    }
}
