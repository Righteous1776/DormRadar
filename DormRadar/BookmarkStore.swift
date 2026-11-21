import Foundation
import SQLite3

final class BookmarkStore {
    private enum StoreError: Error {
        case sqlite(Int32)
        case invalidRecord
        case unsupportedSchema
    }

    private let db: OpaquePointer

    static func openDefault() throws -> BookmarkStore {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return try BookmarkStore(url: directory.appendingPathComponent("DeviceBookmarks.sqlite3"))
    }

    init(url: URL) throws {
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw StoreError.sqlite(result)
        }
        db = connection
        sqlite3_busy_timeout(db, 1_000)
        try configure()
    }

    deinit { sqlite3_close(db) }

    private func configure() throws {
        let version = try withStatement("PRAGMA user_version") { statement in
            try check(sqlite3_step(statement), expecting: SQLITE_ROW)
            return sqlite3_column_int(statement, 0)
        }
        guard version <= 1 else { throw StoreError.unsupportedSchema }
        guard version == 0 else { return }
        try transaction {
            try execute("""
                CREATE TABLE IF NOT EXISTS device_bookmarks (
                    id TEXT PRIMARY KEY NOT NULL,
                    updated_at REAL NOT NULL,
                    payload BLOB NOT NULL
                )
                """)
            try execute("PRAGMA user_version = 1")
        }
    }

    func loadBookmarks() throws -> [DeviceBookmark] {
        try withStatement("SELECT payload FROM device_bookmarks ORDER BY updated_at DESC, id") { statement in
            var bookmarks: [DeviceBookmark] = []
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(statement, 0) else { throw StoreError.invalidRecord }
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
                bookmarks.append(try JSONDecoder().decode(DeviceBookmark.self, from: data))
                result = sqlite3_step(statement)
            }
            try check(result, expecting: SQLITE_DONE)
            return bookmarks
        }
    }

    func migrateLegacy(_ bookmarks: [DeviceBookmark]) throws {
        try transaction {
            for bookmark in bookmarks {
                var item = bookmark
                item.normalize()
                try write(item, sql: "INSERT OR IGNORE INTO device_bookmarks VALUES (?, ?, ?)")
            }
        }
    }

    func save(_ bookmark: DeviceBookmark) throws {
        try write(bookmark, sql: """
            INSERT INTO device_bookmarks VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, payload = excluded.payload
            """)
    }

    func remove(id: UUID) throws {
        try withStatement("DELETE FROM device_bookmarks WHERE id = ?") { statement in
            try bindID(id, to: statement)
            try check(sqlite3_step(statement), expecting: SQLITE_DONE)
        }
    }

    private func write(_ bookmark: DeviceBookmark, sql: String) throws {
        let data = try JSONEncoder().encode(bookmark)
        try withStatement(sql) { statement in
            try bindID(bookmark.id, to: statement)
            try check(sqlite3_bind_double(statement, 2, bookmark.updatedAt.timeIntervalSince1970))
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            try data.withUnsafeBytes { bytes in
                try check(sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(bytes.count), transient))
            }
            try check(sqlite3_step(statement), expecting: SQLITE_DONE)
        }
    }

    private func bindID(_ id: UUID, to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        try check(sqlite3_bind_text(statement, 1, id.uuidString, -1, transient))
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(db, sql, nil, nil, nil))
    }

    private func withStatement<T>(_ sql: String, _ operation: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil))
        guard let statement else { throw StoreError.invalidRecord }
        defer { sqlite3_finalize(statement) }
        return try operation(statement)
    }

    private func check(_ result: Int32, expecting expected: Int32 = SQLITE_OK) throws {
        guard result == expected else { throw StoreError.sqlite(result) }
    }
}
