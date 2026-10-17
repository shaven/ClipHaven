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

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
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
    private var db: OpaquePointer?

    public init(url: URL, limits: Limits = Limits()) throws {
        self.url = url
        self.limits = limits
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = SQLiteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
            sqlite3_close(db)
            throw error
        }
        // Wait out another connection's lock (e.g. a backup or sqlite3 reading at launch)
        // instead of failing at once with SQLITE_BUSY.
        sqlite3_busy_timeout(db, 5_000)
        try exec("""
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
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

    deinit {
        sqlite3_close(db)
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
            let id = sqlite3_last_insert_rowid(db)
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

    // MARK: - Reading

    /// Clips newest first.
    public func fetch(limit: Int, offset: Int = 0) throws -> [StoredClip] {
        let rows = try query("SELECT id, title, created FROM clips ORDER BY seq DESC LIMIT ? OFFSET ?",
                             [.int(Int64(limit)), .int(Int64(offset))]) { stmt in
            (sqlite3_column_int64(stmt, 0), Self.text(stmt, 1), sqlite3_column_double(stmt, 2))
        }
        return try rows.map { id, title, created in
            let reps = try query("SELECT type, data FROM representations WHERE clip_id = ? ORDER BY rowid", [.int(id)]) {
                Representation(type: Self.text($0, 0), data: Self.blob($0, 1))
            }
            return StoredClip(id: id, title: title, created: Date(timeIntervalSince1970: created), representations: reps)
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

    private enum Value {
        case int(Int64), double(Double), text(String), blob(Data)
    }

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

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        _ = try query(sql, values) { _ in () }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        Int(try query(sql, []) { sqlite3_column_int64($0, 0) }.first ?? 0)
    }

    private func query<T>(_ sql: String, _ values: [Value], row: (OpaquePointer) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw lastError() }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, value) in values.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(stmt, index, v)
            case .double(let v): sqlite3_bind_double(stmt, index, v)
            case .text(let v): sqlite3_bind_text(stmt, index, v, -1, transient)
            case .blob(let v):
                _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(v.count), transient) }
            }
        }
        var rows: [T] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: rows.append(row(stmt))
            case SQLITE_DONE: return rows
            default: throw lastError()
            }
        }
    }

    private func lastError() -> SQLiteError {
        SQLiteError(code: sqlite3_errcode(db), message: String(cString: sqlite3_errmsg(db)))
    }

    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }

    private static func blob(_ stmt: OpaquePointer, _ column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, column)))
    }
}
