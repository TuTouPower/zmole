import Foundation
import SQLite3

enum DiskSessionStoreError: Error, Equatable, LocalizedError, Sendable {
    case openFailed(String)
    case queryFailed(String)
    case storageQuotaExceeded
    case closed

    var errorDescription: String? {
        switch self {
        case .openFailed(let reason): return "无法打开磁盘会话临时数据库: \(reason)"
        case .queryFailed(let reason): return "磁盘会话数据库查询失败: \(reason)"
        case .storageQuotaExceeded: return "磁盘会话临时空间超出上限"
        case .closed: return "磁盘会话临时数据库已关闭"
        }
    }
}

struct DiskLevelSummary: Equatable, Sendable {
    let path: String
    let totalSize: Int64
    let selfDeduplicatedSize: Int64
    let isReadable: Bool
    let directFilesCount: Int
    let directDirectoriesCount: Int
}

/// Backing store for disk measurement session that holds directory entries,
/// subtree inode facts, and level summaries on disk with pagination support.
final class DiskSessionStore: @unchecked Sendable {
    let fileURL: URL
    let maxStorageBytes: Int64

    private let lock = NSLock()
    private var db: OpaquePointer?
    private var isClosed = false

    init(fileURL: URL? = nil, maxStorageBytes: Int64 = 100 * 1024 * 1024) throws {
        let targetURL = fileURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole_disk_session_\(UUID().uuidString).sqlite")
        self.fileURL = targetURL
        self.maxStorageBytes = maxStorageBytes

        var dbPointer: OpaquePointer?
        if sqlite3_open_v2(
            targetURL.path,
            &dbPointer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) != SQLITE_OK {
            let msg = dbPointer != nil ? String(cString: sqlite3_errmsg(dbPointer)) : "unknown"
            if let dbPointer { sqlite3_close(dbPointer) }
            throw DiskSessionStoreError.openFailed(msg)
        }
        self.db = dbPointer

        try initSchema()
    }

    deinit {
        close()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func checkQuota() throws {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64, size >= maxStorageBytes {
            throw DiskSessionStoreError.storageQuotaExceeded
        }
    }

    private func initSchema() throws {
        let sql = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;

        CREATE TABLE IF NOT EXISTS levels (
            path TEXT PRIMARY KEY,
            total_size INTEGER,
            self_size INTEGER,
            files_total INTEGER,
            is_readable INTEGER,
            files_count INTEGER,
            dirs_count INTEGER
        );

        CREATE TABLE IF NOT EXISTS entries (
            parent_path TEXT,
            name TEXT,
            path TEXT,
            is_dir INTEGER,
            value_type INTEGER,
            size INTEGER,
            link_dev INTEGER,
            link_ino INTEGER,
            self_size INTEGER,
            parent_contrib INTEGER,
            PRIMARY KEY (parent_path, path)
        );

        CREATE INDEX IF NOT EXISTS idx_entries_parent ON entries (parent_path, name);

        CREATE TABLE IF NOT EXISTS inodes (
            root_path TEXT,
            dev INTEGER,
            ino INTEGER,
            size INTEGER,
            PRIMARY KEY (root_path, dev, ino)
        );
        """
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw DiskSessionStoreError.closed }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DiskSessionStoreError.queryFailed(msg)
        }
    }

    func saveLevel(
        summary: DiskLevelSummary,
        entries: [DiskEntry],
        inodes: [HardLinkKey: Int64]
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db, !isClosed else { throw DiskSessionStoreError.closed }
        try checkQuota()

        _ = sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        // 1. Insert or replace into levels
        let levelSQL = "INSERT OR REPLACE INTO levels VALUES (?, ?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, levelSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (summary.path as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 2, summary.totalSize)
            sqlite3_bind_int64(stmt, 3, summary.selfDeduplicatedSize)
            sqlite3_bind_int64(stmt, 4, 0)
            sqlite3_bind_int(stmt, 5, summary.isReadable ? 1 : 0)
            sqlite3_bind_int(stmt, 6, Int32(summary.directFilesCount))
            sqlite3_bind_int(stmt, 7, Int32(summary.directDirectoriesCount))
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // 2. Insert or replace entries
        let entrySQL = "INSERT OR REPLACE INTO entries VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, entrySQL, -1, &stmt, nil) == SQLITE_OK {
            for entry in entries {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, (summary.path as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (entry.name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (entry.path as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 4, entry.isDirectory ? 1 : 0)

                let valueType: Int32
                var sizeVal: Int64 = 0
                switch entry.value {
                case .size(let s):
                    valueType = 0
                    sizeVal = s
                case .computing:
                    valueType = 1
                case .unreadable:
                    valueType = 2
                case .otherDevice:
                    valueType = 3
                }
                sqlite3_bind_int(stmt, 5, valueType)
                sqlite3_bind_int64(stmt, 6, sizeVal)

                if let key = entry.linkKey {
                    sqlite3_bind_int64(stmt, 7, Int64(key.device))
                    sqlite3_bind_int64(stmt, 8, Int64(key.inode))
                } else {
                    sqlite3_bind_null(stmt, 7)
                    sqlite3_bind_null(stmt, 8)
                }

                if let selfSize = entry.selfDeduplicatedSize {
                    sqlite3_bind_int64(stmt, 9, selfSize)
                } else {
                    sqlite3_bind_null(stmt, 9)
                }

                if let contrib = entry.parentContribution {
                    sqlite3_bind_int64(stmt, 10, contrib)
                } else {
                    sqlite3_bind_null(stmt, 10)
                }

                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }

        // 3. Insert or replace inodes
        let inodeSQL = "INSERT OR REPLACE INTO inodes VALUES (?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, inodeSQL, -1, &stmt, nil) == SQLITE_OK {
            for (key, size) in inodes {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, (summary.path as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(stmt, 2, Int64(key.device))
                sqlite3_bind_int64(stmt, 3, Int64(key.inode))
                sqlite3_bind_int64(stmt, 4, size)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }

        _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    func loadSummary(for path: String) -> DiskLevelSummary? {
        lock.lock()
        defer { lock.unlock() }
        guard let db, !isClosed else { return nil }

        let sql = "SELECT total_size, self_size, is_readable, files_count, dirs_count FROM levels WHERE path = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let total = sqlite3_column_int64(stmt, 0)
            let selfSize = sqlite3_column_int64(stmt, 1)
            let isReadable = sqlite3_column_int(stmt, 2) != 0
            let filesCount = Int(sqlite3_column_int(stmt, 3))
            let dirsCount = Int(sqlite3_column_int(stmt, 4))
            return DiskLevelSummary(
                path: path,
                totalSize: total,
                selfDeduplicatedSize: selfSize,
                isReadable: isReadable,
                directFilesCount: filesCount,
                directDirectoriesCount: dirsCount
            )
        }
        return nil
    }

    func countEntries(parentPath: String, search: String = "") -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db, !isClosed else { return 0 }

        let sql: String
        if search.isEmpty {
            sql = "SELECT COUNT(*) FROM entries WHERE parent_path = ?;"
        } else {
            sql = "SELECT COUNT(*) FROM entries WHERE parent_path = ? AND name LIKE ?;"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (parentPath as NSString).utf8String, -1, nil)
        if !search.isEmpty {
            let pattern = "%\(search)%"
            sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    func loadEntries(
        parentPath: String,
        offset: Int = 0,
        limit: Int = 4000,
        search: String = "",
        sort: AnalyzeSort = .name
    ) throws -> [DiskEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db, !isClosed else { throw DiskSessionStoreError.closed }

        var sql = "SELECT name, path, is_dir, value_type, size, link_dev, link_ino, self_size, parent_contrib FROM entries WHERE parent_path = ?"
        if !search.isEmpty {
            sql += " AND name LIKE ?"
        }

        switch sort {
        case .name:
            sql += " ORDER BY name COLLATE NOCASE ASC, path ASC"
        case .size:
            // value_type 0 is known size, others computing/unreadable (put at end)
            sql += " ORDER BY CASE WHEN value_type = 0 THEN 0 ELSE 1 END ASC, size DESC, name COLLATE NOCASE DESC, path ASC"
        }
        sql += " LIMIT ? OFFSET ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DiskSessionStoreError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        var bindIdx: Int32 = 1
        sqlite3_bind_text(stmt, bindIdx, (parentPath as NSString).utf8String, -1, nil)
        bindIdx += 1

        if !search.isEmpty {
            let pattern = "%\(search)%"
            sqlite3_bind_text(stmt, bindIdx, (pattern as NSString).utf8String, -1, nil)
            bindIdx += 1
        }

        sqlite3_bind_int(stmt, bindIdx, Int32(limit))
        bindIdx += 1
        sqlite3_bind_int(stmt, bindIdx, Int32(offset))

        var results: [DiskEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0),
                  let pathPtr = sqlite3_column_text(stmt, 1) else { continue }
            let name = String(cString: namePtr)
            let path = String(cString: pathPtr)
            let isDir = sqlite3_column_int(stmt, 2) != 0
            let valueType = sqlite3_column_int(stmt, 3)
            let size = sqlite3_column_int64(stmt, 4)

            let entryValue: DiskEntryValue
            switch valueType {
            case 0: entryValue = .size(size)
            case 1: entryValue = .computing
            case 2: entryValue = .unreadable
            case 3: entryValue = .otherDevice
            default: entryValue = .computing
            }

            var linkKey: HardLinkKey?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL, sqlite3_column_type(stmt, 6) != SQLITE_NULL {
                let dev = UInt64(bitPattern: sqlite3_column_int64(stmt, 5))
                let ino = UInt64(bitPattern: sqlite3_column_int64(stmt, 6))
                linkKey = HardLinkKey(device: dev, inode: ino)
            }

            var selfSize: Int64?
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                selfSize = sqlite3_column_int64(stmt, 7)
            }

            var parentContrib: Int64?
            if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
                parentContrib = sqlite3_column_int64(stmt, 8)
            }

            results.append(DiskEntry(
                name: name,
                path: path,
                isDirectory: isDir,
                value: entryValue,
                linkKey: linkKey,
                selfDeduplicatedSize: selfSize,
                parentContribution: parentContrib
            ))
        }

        return results
    }

    func loadInodes(for rootPath: String) -> [HardLinkKey: Int64] {
        lock.lock()
        defer { lock.unlock() }
        guard let db, !isClosed else { return [:] }

        let sql = "SELECT dev, ino, size FROM inodes WHERE root_path = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (rootPath as NSString).utf8String, -1, nil)
        var map: [HardLinkKey: Int64] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let dev = UInt64(bitPattern: sqlite3_column_int64(stmt, 0))
            let ino = UInt64(bitPattern: sqlite3_column_int64(stmt, 1))
            let size = sqlite3_column_int64(stmt, 2)
            map[HardLinkKey(device: dev, inode: ino)] = size
        }
        return map
    }

    func clearSubtree(path: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db, !isClosed else { return }

        let prefix = path.hasSuffix("/") ? path : path + "/"
        let pattern = prefix + "%"

        let sql = """
        DELETE FROM levels WHERE path = ? OR path LIKE ?;
        DELETE FROM entries WHERE parent_path = ? OR parent_path LIKE ?;
        DELETE FROM inodes WHERE root_path = ? OR root_path LIKE ?;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (path as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (path as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (pattern as NSString).utf8String, -1, nil)
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
}
