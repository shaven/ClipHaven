import CryptoKit
import Foundation
import SQLite3

/// One pasteboard type of a clip and its bytes, e.g. `public.rtf` and the RTF data.
public struct Representation: Equatable, Sendable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

/// A clip as stored in history.
public struct StoredClip: Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let created: Date
    public let representations: [Representation]
}

/// A clip without its bytes: what the menu needs, cheap to read for the whole history.
public struct ClipSummary: Equatable, Sendable {
    public let id: Int64
    public let title: String
    /// The first type stored for the clip, e.g. `public.utf8-plain-text`.
    public let primaryType: String

    public init(id: Int64, title: String, primaryType: String) {
        self.id = id
        self.title = title
        self.primaryType = primaryType
    }
}

/// Clip history in one SQLite file: one row per clip, one row per type representation.
///
/// Every change is a row-level insert, update or delete in WAL mode, so adding a clip never
/// rewrites the whole history (unlike ClipMenu's single `clips.data` plist).
public final class HistoryStore {
    public struct Limits: Sendable {
        /// Clips kept; the oldest beyond this are deleted.
        public var maxCount: Int
        /// An image representation larger than this is not stored.
        public var maxImageBytes: Int

        public init(maxCount: Int = 1_000, maxImageBytes: Int = 10_000_000) {
            self.maxCount = maxCount
            self.maxImageBytes = maxImageBytes
        }
    }

    /// Types the per-image byte cap applies to.
    public static let imageTypes: Set<String> = [
        "public.tiff", "public.png", "public.jpeg", "public.heic", "com.apple.pict", "NeXT TIFF v4.0 pasteboard type",
    ]

    public let url: URL
    public let limits: Limits
    private let database: SQLiteDatabase

    public init(url: URL, limits: Limits = Limits()) throws {
        self.url = url
        self.limits = limits
        database = try SQLiteDatabase(url: url)
        try exec("""
            CREATE TABLE IF NOT EXISTS clips (
                id      INTEGER PRIMARY KEY,
                hash    BLOB    NOT NULL UNIQUE,
                title   TEXT    NOT NULL,
                created REAL    NOT NULL,
                seq     INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS clips_seq ON clips (seq);
            CREATE TABLE IF NOT EXISTS representations (
                clip_id INTEGER NOT NULL REFERENCES clips (id) ON DELETE CASCADE,
                type    TEXT    NOT NULL,
                data    BLOB    NOT NULL,
                PRIMARY KEY (clip_id, type)
            );
            PRAGMA user_version = 1;
            """)
    }

    // MARK: - Writing

    /// Stores a clip at the top of history and returns its id. A clip already in history moves
    /// to the top instead. Image representations over the byte cap are dropped; if nothing is
    /// left, nothing is stored and the result is nil.
    @discardableResult
    public func insert(_ representations: [Representation], title: String, created: Date = Date()) throws -> Int64? {
        let kept = representations.filter {
            !Self.imageTypes.contains($0.type) || $0.data.count <= limits.maxImageBytes
        }
        guard !kept.isEmpty else { return nil }
        let hash = Self.hash(kept)

        return try transaction {
            let seq = try nextSeq()
            let existing = try query("SELECT id FROM clips WHERE hash = ?", [.blob(hash)]) { sqlite3_column_int64($0, 0) }.first
            if let id = existing {
                try run("UPDATE clips SET seq = ? WHERE id = ?", [.int(seq), .int(id)])
                return id
            }
            try run("INSERT INTO clips (hash, title, created, seq) VALUES (?, ?, ?, ?)",
                    [.blob(hash), .text(title), .double(created.timeIntervalSince1970), .int(seq)])
            let id = database.lastInsertRowID
            for rep in kept {
                try run("INSERT OR REPLACE INTO representations (clip_id, type, data) VALUES (?, ?, ?)",
                        [.int(id), .text(rep.type), .blob(rep.data)])
            }
            try run("DELETE FROM clips WHERE id IN (SELECT id FROM clips ORDER BY seq DESC LIMIT -1 OFFSET ?)",
                    [.int(Int64(limits.maxCount))])
            return id
        }
    }

    public func delete(id: Int64) throws {
        try run("DELETE FROM clips WHERE id = ?", [.int(id)])
    }

    /// Moves a clip to the top of history, as ClipMenu does after pasting it.
    public func moveToTop(id: Int64) throws {
        try transaction {
            try run("UPDATE clips SET seq = ? WHERE id = ?", [.int(try nextSeq()), .int(id)])
        }
    }

    public func clear() throws {
        try run("DELETE FROM clips", [])
    }

    // MARK: - Reading

    /// Clips newest first.
    public func fetch(limit: Int, offset: Int = 0) throws -> [StoredClip] {
        let rows = try query("SELECT id, title, created FROM clips ORDER BY seq DESC LIMIT ? OFFSET ?",
                             [.int(Int64(limit)), .int(Int64(offset))]) { stmt in
            (sqlite3_column_int64(stmt, 0), Self.text(stmt, 1), sqlite3_column_double(stmt, 2))
        }
        return try rows.map { id, title, created in
            StoredClip(id: id, title: title, created: Date(timeIntervalSince1970: created), representations: try representations(of: id))
        }
    }

    /// Clips newest first, without their representations.
    public func summaries(limit: Int) throws -> [ClipSummary] {
        try query("""
            SELECT c.id, c.title,
                   (SELECT type FROM representations r WHERE r.clip_id = c.id ORDER BY rowid LIMIT 1)
            FROM clips c ORDER BY c.seq DESC LIMIT ?
            """, [.int(Int64(limit))]) { stmt in
            ClipSummary(id: sqlite3_column_int64(stmt, 0), title: Self.text(stmt, 1), primaryType: Self.text(stmt, 2))
        }
    }

    public func clip(id: Int64) throws -> StoredClip? {
        let rows = try query("SELECT title, created FROM clips WHERE id = ?", [.int(id)]) { stmt in
            (Self.text(stmt, 0), sqlite3_column_double(stmt, 1))
        }
        guard let (title, created) = rows.first else { return nil }
        return StoredClip(id: id, title: title, created: Date(timeIntervalSince1970: created), representations: try representations(of: id))
    }

    private func representations(of id: Int64) throws -> [Representation] {
        try query("SELECT type, data FROM representations WHERE clip_id = ? ORDER BY rowid", [.int(id)]) {
            Representation(type: Self.text($0, 0), data: Self.blob($0, 1))
        }
    }

    public func count() throws -> Int {
        try scalarInt("SELECT count(*) FROM clips")
    }

    // MARK: - Inspection (tests and diagnostics)

    func representationRowCount() throws -> Int {
        try scalarInt("SELECT count(*) FROM representations")
    }

    func journalMode() throws -> String {
        try query("PRAGMA journal_mode", []) { Self.text($0, 0) }.first ?? ""
    }

    /// Folds the WAL back into the main file so its size reflects what is stored.
    func checkpoint() throws {
        try exec("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    func fileSize() throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    // MARK: - SQLite plumbing

    private static func hash(_ reps: [Representation]) -> Data {
        var hasher = SHA256()
        for rep in reps.sorted(by: { $0.type < $1.type }) {
            hasher.update(data: Data(rep.type.utf8))
            hasher.update(data: withUnsafeBytes(of: UInt64(rep.data.count).bigEndian) { Data($0) })
            hasher.update(data: rep.data)
        }
        return Data(hasher.finalize())
    }

    private func nextSeq() throws -> Int64 {
        Int64(try scalarInt("SELECT coalesce(max(seq), 0) + 1 FROM clips"))
    }

    private typealias Value = SQLiteDatabase.Value

    private func transaction<T>(_ body: () throws -> T) throws -> T { try database.transaction(body) }
    private func exec(_ sql: String) throws { try database.exec(sql) }
    private func run(_ sql: String, _ values: [Value]) throws { try database.run(sql, values) }
    private func scalarInt(_ sql: String) throws -> Int { try database.scalarInt(sql) }
    private func query<T>(_ sql: String, _ values: [Value], row: (OpaquePointer) -> T) throws -> [T] {
        try database.query(sql, values, row: row)
    }

    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String { SQLiteDatabase.text(stmt, column) }
    private static func blob(_ stmt: OpaquePointer, _ column: Int32) -> Data { SQLiteDatabase.blob(stmt, column) }
}
