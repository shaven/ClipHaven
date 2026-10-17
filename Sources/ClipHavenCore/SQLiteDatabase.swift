import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// One connection to ClipHaven's SQLite file in WAL mode. History and snippets each open their
/// own, so they share the file and not a lock.
final class SQLiteDatabase {
    enum Value {
        case int(Int64), double(Double), text(String), blob(Data)
    }

    private var db: OpaquePointer?

    init(url: URL) throws {
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
            """)
    }

    deinit {
        sqlite3_close(db)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
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

    func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    func run(_ sql: String, _ values: [Value]) throws {
        _ = try query(sql, values) { _ in () }
    }

    func scalarInt(_ sql: String) throws -> Int {
        Int(try query(sql, []) { sqlite3_column_int64($0, 0) }.first ?? 0)
    }

    func query<T>(_ sql: String, _ values: [Value], row: (OpaquePointer) -> T) throws -> [T] {
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

    static func int(_ stmt: OpaquePointer, _ column: Int32) -> Int64 {
        sqlite3_column_int64(stmt, column)
    }

    static func text(_ stmt: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }

    static func blob(_ stmt: OpaquePointer, _ column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, column)))
    }
}
