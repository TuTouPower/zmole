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

/// Complete facts live in SQLite. Readers only materialize the requested page.
/// Each walk writes a private staging database; promotion is one transaction.
final class DiskSessionStore: @unchecked Sendable {
    let fileURL: URL
    let maxStorageBytes: Int64
    private let lock = NSRecursiveLock()
    private let budget: DiskStorageBudget
    private var db: OpaquePointer?
    private var openingError: DiskSessionStoreError?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(fileURL: URL? = nil, maxStorageBytes: Int64 = 100 * 1024 * 1024, budget: DiskStorageBudget? = nil) throws {
        self.fileURL = fileURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("zmole_disk_session_\(UUID().uuidString).sqlite")
        self.maxStorageBytes = maxStorageBytes
        self.budget = budget ?? DiskStorageBudget(limit: maxStorageBytes)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(self.fileURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            throw DiskSessionStoreError.openFailed(self.fileURL.lastPathComponent)
        }
        db = handle
        sqlite3_create_collation_v2(handle, "mole_name", SQLITE_UTF8, nil, { _, leftCount, left, rightCount, right in
            guard let left, let right else { return 0 }
            let lhs = String(decoding: UnsafeBufferPointer(start: left.assumingMemoryBound(to: UInt8.self), count: Int(leftCount)), as: UTF8.self)
            let rhs = String(decoding: UnsafeBufferPointer(start: right.assumingMemoryBound(to: UInt8.self), count: Int(rightCount)), as: UTF8.self)
            return Int32(lhs.localizedStandardCompare(rhs).rawValue)
        }, nil)
        sqlite3_create_function_v2(handle, "mole_contains", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, _, arguments in
            guard let arguments, let lhs = sqlite3_value_text(arguments[0]), let rhs = sqlite3_value_text(arguments[1]) else {
                sqlite3_result_int(context, 0)
                return
            }
            let search = String(cString: rhs)
            sqlite3_result_int(context, search.isEmpty || String(cString: lhs).localizedCaseInsensitiveContains(search) ? 1 : 0)
        }, nil, nil, nil)
        self.budget.register(self.fileURL.path)
        do {
            try exec("PRAGMA journal_mode = DELETE;")
            try exec("PRAGMA cache_size = -256;")
            try exec("CREATE TABLE levels (path TEXT PRIMARY KEY, total_size INTEGER, self_size INTEGER, readable INTEGER, files_count INTEGER, dirs_count INTEGER, complete INTEGER, base_size INTEGER, local_readable INTEGER);")
            try exec("CREATE TABLE entries (parent_path TEXT, name TEXT, path TEXT, is_dir INTEGER, value_type INTEGER, size INTEGER, link_dev INTEGER, link_ino INTEGER, self_size INTEGER, parent_contrib INTEGER, PRIMARY KEY(parent_path, path));")
            try exec("CREATE INDEX entry_scope ON entries(parent_path, link_dev, link_ino);")
            try exec("CREATE TABLE browser_queue (path TEXT PRIMARY KEY, generation INTEGER);")
            try exec("CREATE TABLE inodes (root_path TEXT, dev INTEGER, ino INTEGER, size INTEGER, PRIMARY KEY(root_path, dev, ino));")
        } catch {
            close()
            throw error
        }
    }

    private init(unavailableError: Error) {
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("zmole_unavailable_\(UUID().uuidString).sqlite")
        maxStorageBytes = 0
        budget = DiskStorageBudget(limit: 0)
        openingError = .openFailed(unavailableError.localizedDescription)
    }

    static func unavailable(_ error: Error) -> DiskSessionStore { DiskSessionStore(unavailableError: error) }

    deinit { close() }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard let handle = db else { return }
        sqlite3_close(handle)
        db = nil
        budget.unregister(fileURL.path)
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: fileURL.path + suffix)
        }
    }

    private func statement<T>(_ sql: String, _ strings: [String] = [], _ body: (OpaquePointer) throws -> T) throws -> T {
        guard let db else { throw openingError ?? .closed }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DiskSessionStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (index, string) in strings.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), string, -1, Self.transient)
        }
        return try body(stmt)
    }

    private func exec(_ sql: String, _ strings: [String] = []) throws {
        try statement(sql, strings) { stmt in
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw queryError() }
        }
    }

    private func queryError() -> DiskSessionStoreError {
        .queryFailed(db.map { String(cString: sqlite3_errmsg($0)) } ?? "closed")
    }

    private func scalar(_ sql: String, _ strings: [String] = []) throws -> Int64 {
        try statement(sql, strings) { stmt in
            guard sqlite3_step(stmt) == SQLITE_ROW else { throw queryError() }
            return sqlite3_column_int64(stmt, 0)
        }
    }

    func makeStagingStore() throws -> DiskSessionStore {
        try DiskSessionStore(maxStorageBytes: maxStorageBytes, budget: budget)
    }

    private func checkQuota() throws {
        try budget.check()
        let pages = try scalar("PRAGMA page_count;")
        let pageSize = try scalar("PRAGMA page_size;")
        let journal = (try? FileManager.default.attributesOfItem(atPath: fileURL.path + "-journal")[.size] as? NSNumber)?.int64Value ?? 0
        guard pages * pageSize + journal <= maxStorageBytes else { throw DiskSessionStoreError.storageQuotaExceeded }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE;")
        do {
            try body()
            try checkQuota()
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func saveLevel(summary: DiskLevelSummary, entries: [DiskEntry], inodes: [HardLinkKey: Int64]) throws {
        lock.lock()
        defer { lock.unlock() }
        try transaction {
            try deleteLevel(summary.path)
            try putSummary(summary, complete: !entries.contains { $0.value == .computing }, base: entries.isEmpty ? summary.totalSize : 0)
            try appendEntriesUnlocked(parent: summary.path, entries: entries)
            for (key, size) in inodes {
                try exec("INSERT INTO inodes VALUES (?, \(Int64(bitPattern: key.device)), \(Int64(bitPattern: key.inode)), \(size));", [summary.path])
            }
        }
    }

    private func deleteLevel(_ path: String) throws {
        for (table, column) in [("entries", "parent_path"), ("inodes", "root_path"), ("levels", "path")] {
            try exec("DELETE FROM \(table) WHERE \(column) = ?;", [path])
        }
    }

    private func putSummary(_ s: DiskLevelSummary, complete: Bool, base: Int64 = 0, localReadable: Bool? = nil) throws {
        try exec("INSERT OR REPLACE INTO levels VALUES (?, \(s.totalSize), \(s.selfDeduplicatedSize), \(s.isReadable ? 1 : 0), \(s.directFilesCount), \(s.directDirectoriesCount), \(complete ? 1 : 0), \(base), \((localReadable ?? s.isReadable) ? 1 : 0));", [s.path])
    }

    func beginLevel(_ path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try transaction {
            try deleteLevel(path)
            try putSummary(.init(path: path, totalSize: 0, selfDeduplicatedSize: 0, isReadable: true, directFilesCount: 0, directDirectoriesCount: 0), complete: false)
        }
    }

    func appendEntries(parent: String, entries: [DiskEntry]) throws {
        lock.lock()
        defer { lock.unlock() }
        try transaction { try appendEntriesUnlocked(parent: parent, entries: entries) }
    }

    private func appendEntriesUnlocked(parent: String, entries: [DiskEntry]) throws {
        for e in entries {
            let kind: Int
            switch e.value {
            case .size: kind = 0
            case .computing: kind = 1
            case .unreadable: kind = 2
            case .otherDevice: kind = 3
            }
            let dev = e.linkKey.map { String(Int64(bitPattern: $0.device)) } ?? "NULL"
            let ino = e.linkKey.map { String(Int64(bitPattern: $0.inode)) } ?? "NULL"
            try exec("INSERT INTO entries VALUES (?, ?, ?, \(e.isDirectory ? 1 : 0), \(kind), \(e.knownSize ?? 0), \(dev), \(ino), \(e.selfDeduplicatedSize.map(String.init) ?? "NULL"), \(e.parentContribution.map(String.init) ?? "NULL")) ON CONFLICT(parent_path,path) DO UPDATE SET name=excluded.name,is_dir=excluded.is_dir,value_type=excluded.value_type,size=excluded.size,link_dev=excluded.link_dev,link_ino=excluded.link_ino,self_size=excluded.self_size,parent_contrib=excluded.parent_contrib;", [parent, e.name, e.path])
        }
    }

    /// Cursor for the scanner's disk-backed work queue. No all-tree path array.
    func nextUnlistedDirectory() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try statement("SELECT path FROM entries WHERE is_dir=1 AND value_type=1 AND path NOT IN (SELECT path FROM levels) ORDER BY path LIMIT 1;") { stmt in
            sqlite3_step(stmt) == SQLITE_ROW ? String(cString: sqlite3_column_text(stmt, 0)) : nil
        }
    }

    func finishLevel(_ path: String, readable: Bool, complete: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        try exec("UPDATE levels SET readable=\(readable ? 1 : 0), local_readable=\(readable ? 1 : 0), complete=\(complete ? 1 : 0) WHERE path=?;", [path])
    }

    func importResult(_ result: DiskScanResult) throws {
        lock.lock()
        defer { lock.unlock() }
        var levels = result.levels
        if levels[result.path] == nil { levels[result.path] = DiskLevel(entries: [], totalSize: result.totalSize) }
        try transaction {
            for (path, level) in levels {
                try deleteLevel(path)
                let unreadable = level.entries.contains { !$0.isDirectory && $0.value == .unreadable }
                let base = level.entries.isEmpty ? level.totalSize : level.entries.filter { entry in entry.isDirectory && !levels.keys.contains { $0 == entry.path || $0.hasPrefix(LiveDiskScanner.directoryPrefix(entry.path)) } }.compactMap(\.knownSize).reduce(0, +)
                try putSummary(.init(path: path, totalSize: level.totalSize, selfDeduplicatedSize: level.totalSize, isReadable: (path != result.path || result.isReadable) && !unreadable, directFilesCount: 0, directDirectoriesCount: 0), complete: true, base: base)
                try appendEntriesUnlocked(parent: path, entries: level.entries)
            }
        }
        try recalculateAll()
    }

    /// Literal prefix range, unaffected by SQL LIKE metacharacters in names.
    private func scope(_ column: String) -> String { "(\(column) = ? OR (\(column) >= ? AND \(column) < ?))" }
    private func bounds(_ path: String) -> [String] {
        let prefix = LiveDiskScanner.directoryPrefix(path)
        return [path, prefix, String(prefix.dropLast()) + "0"]
    }

    private func reachable(_ column: String) -> String {
        "NOT EXISTS (SELECT 1 FROM entries boundary WHERE boundary.is_dir=1 AND boundary.value_type=3 AND \(scope("boundary.parent_path")) AND (\(column)=boundary.path OR substr(\(column),1,length(boundary.path)+1)=boundary.path||'/'))"
    }

    private func selfTotal(_ path: String) throws -> Int64 {
        let args = bounds(path)
        return try scalar("""
            SELECT COALESCE(SUM(bytes),0) FROM (
                SELECT e.size AS bytes FROM entries e WHERE \(scope("e.parent_path")) AND \(reachable("e.parent_path")) AND e.is_dir=0 AND e.value_type=0 AND e.link_dev IS NULL
                UNION ALL SELECT MAX(e.size) FROM entries e WHERE \(scope("e.parent_path")) AND \(reachable("e.parent_path")) AND e.is_dir=0 AND e.value_type=0 AND e.link_dev IS NOT NULL GROUP BY e.link_dev,e.link_ino
                UNION ALL SELECT l.base_size FROM levels l WHERE \(scope("l.path")) AND \(reachable("l.path"))
            );
            """, args + args + args + args + args + args)
    }

    private func contribution(child: String, parent: String, ownSize: Int64) throws -> Int64 {
        let duplicates = try scalar("""
            SELECT COALESCE(SUM(bytes),0) FROM (
                SELECT MAX(c.size) AS bytes FROM entries c WHERE \(scope("c.parent_path")) AND c.is_dir=0 AND c.value_type=0 AND c.link_dev IS NOT NULL
                AND EXISTS (SELECT 1 FROM entries p WHERE \(scope("p.parent_path")) AND \(reachable("p.parent_path")) AND p.is_dir=0 AND p.value_type=0 AND p.link_dev=c.link_dev AND p.link_ino=c.link_ino AND (p.parent_path=? OR p.parent_path<?))
                GROUP BY c.link_dev,c.link_ino
            );
            """, bounds(child) + bounds(parent) + bounds(parent) + [parent, child])
        return max(0, ownSize - duplicates)
    }

    func recalculateAll() throws {
        lock.lock()
        defer { lock.unlock() }
        // One row at a time, deepest first, so incomplete children propagate.
        var lastLength = Int.max
        var lastPath = ""
        while let path: String = try statement("SELECT path FROM levels WHERE length(path) < \(lastLength) OR (length(path) = \(lastLength) AND path > ?) ORDER BY length(path) DESC, path ASC LIMIT 1;", [lastPath], { stmt in
            sqlite3_step(stmt) == SQLITE_ROW ? String(cString: sqlite3_column_text(stmt, 0)) : nil
        }) {
            try Task.checkCancellation()
            try recalculate(path)
            lastLength = path.unicodeScalars.count
            lastPath = path
        }
    }

    private func recalculate(_ path: String) throws {
        guard loadSummary(for: path) != nil else { return }
        let localReadable = (try scalar("SELECT local_readable FROM levels WHERE path=?;", [path])) != 0
        var readable = localReadable
        var complete = true
        var files = 0
        var dirs = 0
        var offset = 0
        while true {
            let page = try loadEntries(parentPath: path, offset: offset, limit: 100)
            if page.isEmpty { break }
            for var e in page {
                if e.isDirectory {
                    dirs += 1
                    if e.value == .otherDevice { continue }
                    if let child = loadSummary(for: e.path) {
                        let own = child.selfDeduplicatedSize
                        e.selfDeduplicatedSize = child.isReadable ? own : nil
                        e.parentContribution = try contribution(child: e.path, parent: path, ownSize: own)
                        e.value = isComplete(e.path) ? (child.isReadable ? .size(e.parentContribution ?? 0) : .unreadable) : .computing
                    }
                } else {
                    files += 1
                }
                if e.value == .computing { complete = false }
                if e.value == .unreadable { readable = false }
                try appendEntriesUnlocked(parent: path, entries: [e])
            }
            offset += page.count
        }
        let total = try selfTotal(path)
        let base = try scalar("SELECT base_size FROM levels WHERE path=?;", [path])
        try putSummary(.init(path: path, totalSize: total, selfDeduplicatedSize: total, isReadable: readable, directFilesCount: files, directDirectoriesCount: dirs), complete: complete, base: base, localReadable: localReadable)
    }

    func enqueueBrowserChildren(of path: String, generation: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        try transaction {
            try exec("INSERT OR REPLACE INTO browser_queue SELECT path, \(generation) FROM entries WHERE parent_path=? AND is_dir=1 AND value_type=1;", [path])
        }
    }

    func takeBrowserRequest(generation: Int) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let path: String? = try statement("SELECT path FROM browser_queue WHERE generation=\(generation) ORDER BY path LIMIT 1;") { stmt in
            sqlite3_step(stmt) == SQLITE_ROW ? String(cString: sqlite3_column_text(stmt, 0)) : nil
        }
        if let path { try exec("DELETE FROM browser_queue WHERE path=?;", [path]) }
        return path
    }

    func hasBrowserRequests(generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ((try? scalar("SELECT COUNT(*) FROM browser_queue WHERE generation=\(generation);")) ?? 0) > 0
    }

    func clearBrowserRequests() {
        lock.lock()
        defer { lock.unlock() }
        try? exec("DELETE FROM browser_queue;")
    }

    func isComplete(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (try? scalar("SELECT complete FROM levels WHERE path=?;", [path])) == 1
    }

    func loadSummary(for path: String) -> DiskLevelSummary? {
        lock.lock()
        defer { lock.unlock() }
        return try? statement("SELECT total_size,self_size,readable,files_count,dirs_count FROM levels WHERE path=?;", [path]) { stmt in
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return DiskLevelSummary(path: path, totalSize: sqlite3_column_int64(stmt, 0), selfDeduplicatedSize: sqlite3_column_int64(stmt, 1), isReadable: sqlite3_column_int(stmt, 2) != 0, directFilesCount: Int(sqlite3_column_int(stmt, 3)), directDirectoriesCount: Int(sqlite3_column_int(stmt, 4)))
        }
    }

    func countEntries(parentPath: String, search: String = "") -> Int {
        lock.lock()
        defer { lock.unlock() }
        return Int((try? scalar("SELECT COUNT(*) FROM entries WHERE parent_path=? AND mole_contains(name,?);", [parentPath, search])) ?? 0)
    }

    func loadEntries(parentPath: String, offset: Int = 0, limit: Int = 4000, search: String = "", sort: AnalyzeSort? = .name) throws -> [DiskEntry] {
        lock.lock()
        defer { lock.unlock() }
        let order = sort == nil ? "rowid" : (sort == .name ? "name COLLATE mole_name ASC,path ASC" : "CASE WHEN value_type=0 THEN 0 ELSE 1 END,size DESC,name COLLATE mole_name ASC,path ASC")
        return try statement("SELECT name,path,is_dir,value_type,size,link_dev,link_ino,self_size,parent_contrib FROM entries WHERE parent_path=? AND mole_contains(name,?) ORDER BY \(order) LIMIT \(max(0,limit)) OFFSET \(max(0,offset));", [parentPath, search]) { stmt in
            var entries: [DiskEntry] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { throw queryError() }
                let size = sqlite3_column_int64(stmt, 4)
                let kind = sqlite3_column_int(stmt, 3)
                let value: DiskEntryValue = kind == 0 ? .size(size) : (kind == 1 ? .computing : (kind == 2 ? .unreadable : .otherDevice))
                let key = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : HardLinkKey(device: UInt64(bitPattern: sqlite3_column_int64(stmt, 5)), inode: UInt64(bitPattern: sqlite3_column_int64(stmt, 6)))
                entries.append(DiskEntry(name: String(cString: sqlite3_column_text(stmt, 0)), path: String(cString: sqlite3_column_text(stmt, 1)), isDirectory: sqlite3_column_int(stmt, 2) != 0, value: value, linkKey: key, selfDeduplicatedSize: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7), parentContribution: sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 8)))
            }
            return entries
        }
    }

    func loadInodes(for rootPath: String) -> [HardLinkKey: Int64] {
        lock.lock()
        defer { lock.unlock() }
        return (try? statement("SELECT dev,ino,size FROM inodes WHERE root_path=?;", [rootPath]) { stmt in
            var result: [HardLinkKey: Int64] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                result[HardLinkKey(device: UInt64(bitPattern: sqlite3_column_int64(stmt, 0)), inode: UInt64(bitPattern: sqlite3_column_int64(stmt, 1)))] = sqlite3_column_int64(stmt, 2)
            }
            return result
        }) ?? [:]
    }

    func clearSubtree(path: String) {
        lock.lock()
        defer { lock.unlock() }
        try? transaction { try clearSubtreeUnlocked(path) }
    }

    private func clearSubtreeUnlocked(_ path: String) throws {
        for (table, column) in [("entries", "parent_path"), ("inodes", "root_path"), ("levels", "path"), ("browser_queue", "path")] {
            try exec("DELETE FROM \(table) WHERE \(scope(column));", bounds(path))
        }
    }

    func promote(_ staging: DiskSessionStore, path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try exec("ATTACH DATABASE ? AS incoming;", [staging.fileURL.path])
        defer { try? exec("DETACH DATABASE incoming;") }
        try transaction {
            try clearSubtreeUnlocked(path)
            for table in ["levels", "entries", "inodes"] { try exec("INSERT OR REPLACE INTO \(table) SELECT * FROM incoming.\(table);") }
            var ancestor = (path as NSString).deletingLastPathComponent
            while !ancestor.isEmpty, ancestor != path {
                if loadSummary(for: ancestor) != nil { try recalculate(ancestor) }
                if ancestor == "/" { break }
                ancestor = (ancestor as NSString).deletingLastPathComponent
            }
        }
    }
}

/// All concurrent staging walks and the published store share one disk quota.
final class DiskStorageBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int64
    private var paths: Set<String> = []

    init(limit: Int64) { self.limit = limit }
    func register(_ path: String) { lock.lock(); defer { lock.unlock() }; paths.insert(path) }
    func unregister(_ path: String) { lock.lock(); defer { lock.unlock() }; paths.remove(path) }
    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        var total: Int64 = 0
        for path in paths {
            for suffix in ["", "-wal", "-shm", "-journal"] {
                let attributes = try? FileManager.default.attributesOfItem(atPath: path + suffix)
                total += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        if total > limit { throw DiskSessionStoreError.storageQuotaExceeded }
    }
}
