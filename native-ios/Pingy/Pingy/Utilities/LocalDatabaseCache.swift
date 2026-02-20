import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor LocalDatabaseCache {
    static let shared = LocalDatabaseCache()

    private var database: OpaquePointer?

    private init() {
        openDatabaseIfNeeded()
        createSchemaIfNeeded()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func loadData(for cacheKey: String, userID: String) -> Data? {
        guard let database else { return nil }
        let sql = """
        SELECT payload
        FROM cache_entries
        WHERE user_id = ? AND cache_key = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            logDatabaseError("Prepare load failed")
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, userID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, cacheKey, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard let bytes = sqlite3_column_blob(statement, 0) else {
            return nil
        }
        let length = Int(sqlite3_column_bytes(statement, 0))
        return Data(bytes: bytes, count: length)
    }

    func saveData(_ data: Data, for cacheKey: String, userID: String) {
        guard let database else { return }
        let sql = """
        INSERT INTO cache_entries (user_id, cache_key, payload, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(user_id, cache_key)
        DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            logDatabaseError("Prepare save failed")
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, userID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, cacheKey, -1, SQLITE_TRANSIENT)

        data.withUnsafeBytes { buffer in
            _ = sqlite3_bind_blob(statement, 3, buffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)

        if sqlite3_step(statement) != SQLITE_DONE {
            logDatabaseError("Save failed")
        }
    }

    func removeUserData(userID: String) {
        guard let database else { return }
        let sql = "DELETE FROM cache_entries WHERE user_id = ?;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            logDatabaseError("Prepare delete failed")
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, userID, -1, SQLITE_TRANSIENT)
        if sqlite3_step(statement) != SQLITE_DONE {
            logDatabaseError("Delete user cache failed")
        }
    }

    private func openDatabaseIfNeeded() {
        if database != nil {
            return
        }

        do {
            let databaseURL = try cacheDatabaseURL()
            let result = sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            )

            if result != SQLITE_OK {
                logDatabaseError("Open database failed")
                if let database {
                    sqlite3_close(database)
                    self.database = nil
                }
            }
        } catch {
            AppLogger.error("Database path initialization failed: \(error.localizedDescription)")
        }
    }

    private func createSchemaIfNeeded() {
        guard let database else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS cache_entries (
            user_id TEXT NOT NULL,
            cache_key TEXT NOT NULL,
            payload BLOB NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (user_id, cache_key)
        );
        """
        if sqlite3_exec(database, sql, nil, nil, nil) != SQLITE_OK {
            logDatabaseError("Create schema failed")
        }
    }

    private func cacheDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("PingyCache", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("cache.sqlite3", isDirectory: false)
    }

    private func logDatabaseError(_ prefix: String) {
        guard let database, let message = sqlite3_errmsg(database) else {
            AppLogger.error(prefix)
            return
        }
        AppLogger.error("\(prefix): \(String(cString: message))")
    }
}
