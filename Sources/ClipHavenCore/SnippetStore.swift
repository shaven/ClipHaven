import Foundation

public struct Snippet: Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let content: String
    public let enabled: Bool
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
                    try insertSnippet(folderID: id, title: snippet.title, content: snippet.content, enabled: snippet.enabled)
                    snippetCount += 1
                }
            }
            return ImportCounts(folders: folders.count, snippets: snippetCount)
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
                                 snippets: folder.snippets.filter(\.enabled).map { SnippetSummary(id: $0.id, title: $0.title) })
        }
    }

    public func snippet(id: Int64) throws -> Snippet? {
        try database.query("SELECT id, title, content, enabled FROM snippets WHERE id = ?", [.int(id)]) {
            Snippet(id: SQLiteDatabase.int($0, 0), title: SQLiteDatabase.text($0, 1), content: SQLiteDatabase.text($0, 2), enabled: SQLiteDatabase.int($0, 3) != 0)
        }.first
    }

    public func folderCount() throws -> Int {
        try database.scalarInt("SELECT count(*) FROM snippet_folders")
    }

    func snippetCount() throws -> Int {
        try database.scalarInt("SELECT count(*) FROM snippets")
    }

    // MARK: - Plumbing

    private func snippets(in folderID: Int64) throws -> [Snippet] {
        try database.query("SELECT id, title, content, enabled FROM snippets WHERE folder_id = ? ORDER BY position, id", [.int(folderID)]) {
            Snippet(id: SQLiteDatabase.int($0, 0), title: SQLiteDatabase.text($0, 1), content: SQLiteDatabase.text($0, 2), enabled: SQLiteDatabase.int($0, 3) != 0)
        }
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
