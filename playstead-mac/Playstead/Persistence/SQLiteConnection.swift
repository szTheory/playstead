import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

enum SQLiteError: Error, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var description: String {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .stepFailed(let msg): return "SQLite step failed: \(msg)"
        case .bindFailed(let msg): return "SQLite bind failed: \(msg)"
        }
    }
}

/// A minimal hand-written wrapper over the system `libsqlite3` — no
/// third-party Swift Package Manager dependency. Prepare/bind/step/
/// finalize plus a `transaction` helper is all this phase needs; the
/// OS-provided library removes both the supply-chain verification
/// burden and the nested-code-signing surface a bundled SPM package
/// would add to notarization.
final class SQLiteConnection {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "dev.playstead.mac.sqlite")

    init(path: String) throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open(path, &handle)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.openFailed(msg)
        }
        self.db = handle
        sqlite3_exec(handle, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
    }

    /// Executes `sql` with no result set, binding `params` positionally.
    func execute(_ sql: String, params: [SQLiteBindable] = []) throws {
        try queue.sync {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(params, to: statement)
            let rc = sqlite3_step(statement)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                throw SQLiteError.stepFailed(lastErrorMessage())
            }
        }
    }

    /// Runs `sql` and maps every result row through `rowMapper`.
    func query<T>(_ sql: String, params: [SQLiteBindable] = [], rowMapper: (SQLiteRow) -> T) throws -> [T] {
        try queue.sync {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(params, to: statement)

            var results: [T] = []
            while true {
                let rc = sqlite3_step(statement)
                if rc == SQLITE_ROW {
                    results.append(rowMapper(SQLiteRow(statement: statement)))
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw SQLiteError.stepFailed(lastErrorMessage())
                }
            }
            return results
        }
    }

    /// Runs `body` inside a `BEGIN`/`COMMIT` transaction, rolling back on error.
    func transaction(_ body: () throws -> Void) throws {
        try queue.sync {
            try execUnlocked("BEGIN;")
            do {
                try body()
                try execUnlocked("COMMIT;")
            } catch {
                try? execUnlocked("ROLLBACK;")
                throw error
            }
        }
    }

    private func execUnlocked(_ sql: String) throws {
        let rc = sqlite3_exec(db, sql, nil, nil, nil)
        guard rc == SQLITE_OK else {
            throw SQLiteError.stepFailed(lastErrorMessage())
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            throw SQLiteError.prepareFailed(lastErrorMessage())
        }
        return statement
    }

    private func bind(_ params: [SQLiteBindable], to statement: OpaquePointer) throws {
        for (index, param) in params.enumerated() {
            let rc = param.bind(to: statement, at: Int32(index + 1))
            guard rc == SQLITE_OK else {
                throw SQLiteError.bindFailed(lastErrorMessage())
            }
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(db))
    }
}

/// A value that can be positionally bound into a prepared statement.
protocol SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32
}

extension String: SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_text(statement, index, self, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
}

extension Int: SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int64(statement, index, Int64(self))
    }
}

extension Optional: SQLiteBindable where Wrapped: SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        switch self {
        case .none: return sqlite3_bind_null(statement, index)
        case .some(let value): return value.bind(to: statement, at: index)
        }
    }
}

/// A single result row, read by column index.
struct SQLiteRow {
    let statement: OpaquePointer

    func string(_ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    func int(_ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }
}
