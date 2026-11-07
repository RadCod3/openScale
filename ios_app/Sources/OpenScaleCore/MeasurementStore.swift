// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SQLite3

public enum StoreError: LocalizedError {
    case database(String), invalidWeight
    public var errorDescription: String? {
        switch self {
        case .database(let reason): "Could not save or load measurements: \(reason)"
        case .invalidWeight: "Enter a weight greater than zero."
        }
    }
}

/// Confined to the calling thread; the app owns this store on MainActor.
public final class MeasurementStore {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            sqlite3_close(db); db = nil; throw StoreError.database(message)
        }
        do {
            try execute("CREATE TABLE IF NOT EXISTS measurements (id TEXT PRIMARY KEY, timestamp REAL NOT NULL UNIQUE, weight REAL NOT NULL CHECK(weight > 0), fields TEXT NOT NULL, source TEXT NOT NULL)")
            try execute("PRAGMA user_version = 1")
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func error() -> StoreError { .database(String(cString: sqlite3_errmsg(db))) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        return statement
    }
    public func all() throws -> [Measurement] {
        let s = try prepare("SELECT id, timestamp, weight, fields, source FROM measurements ORDER BY timestamp DESC")
        defer { sqlite3_finalize(s) }
        var result: [Measurement] = []
        while true {
            let status = sqlite3_step(s)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw error() }
            func text(_ i: Int32) -> String { String(cString: sqlite3_column_text(s, i)) }
            guard let id = UUID(uuidString: text(0)) else { throw StoreError.database("Invalid measurement identifier") }
            let fields = try JSONDecoder().decode([String: String].self, from: Data(text(3).utf8))
            result.append(Measurement(id: id, date: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)),
                                      weightKg: sqlite3_column_double(s, 2), fields: fields, source: text(4)))
        }
    }
    /// An entire import commits or rolls back. Timestamp collisions preserve the existing record.
    @discardableResult public func insert(_ measurements: [Measurement]) throws -> Int {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let s = try prepare("INSERT INTO measurements(id, timestamp, weight, fields, source) VALUES (?, ?, ?, ?, ?) ON CONFLICT(timestamp) DO NOTHING")
            defer { sqlite3_finalize(s) }
            var count = 0
            for m in measurements {
                guard m.weightKg.isFinite, m.weightKg > 0, m.weightKg < 1000, m.date.timeIntervalSince1970.isFinite else { throw StoreError.invalidWeight }
                sqlite3_reset(s); sqlite3_clear_bindings(s)
                let fields = String(decoding: try JSONEncoder().encode(m.fields), as: UTF8.self)
                sqlite3_bind_text(s, 1, m.id.uuidString, -1, transient)
                sqlite3_bind_double(s, 2, m.date.timeIntervalSince1970)
                sqlite3_bind_double(s, 3, m.weightKg)
                sqlite3_bind_text(s, 4, fields, -1, transient)
                sqlite3_bind_text(s, 5, m.source, -1, transient)
                guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
                count += Int(sqlite3_changes(db))
            }
            try execute("COMMIT"); return count
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func delete(id: UUID) throws {
        let s = try prepare("DELETE FROM measurements WHERE id = ?"); defer { sqlite3_finalize(s) }
        sqlite3_bind_text(s, 1, id.uuidString, -1, transient)
        guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
    }
}
