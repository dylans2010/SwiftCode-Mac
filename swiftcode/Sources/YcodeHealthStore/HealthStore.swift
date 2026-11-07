import CSQLite
import Foundation
import YcodeSimFeatures

public enum HealthStoreError: Error, CustomStringConvertible, Equatable {
    case noStore(String)
    case sqlite(String)
    case notShutDown

    public var description: String {
        switch self {
        case .noStore(let p): "no health store at \(p) (healthd makes it at the device's first boot)"
        case .sqlite(let m): "health store: \(m)"
        case .notShutDown: "the device is running: its health store belongs to healthd until it shuts down"
        }
    }
}

public enum HealthAuthorizationCode {
    public static let notDetermined = 100, sharingAuthorized = 101, readDenied = 102, sharingDenied = 103, bothDenied = 104
    public static let neverPresented = [0, 200], readPresented = 202, sharePresented = 203
}

public final class SQLiteDatabase {
    private var db: OpaquePointer?
    public let path: String

    public init(path: String, create: Bool = false) throws {
        self.path = path
        let flags = SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let m = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(db)
            db = nil
            throw HealthStoreError.sqlite("\(path): \(m)")
        }
        sqlite3_busy_timeout(db, 5000)
    }

    deinit { sqlite3_close(db) }

    public enum Value: Equatable, Sendable {
        case null, int(Int64), real(Double), text(String), blob([UInt8])
        public var int: Int? { if case .int(let v) = self { Int(v) } else if case .real(let d) = self { Int(d) } else { nil } }
        public var real: Double? { if case .real(let v) = self { v } else if case .int(let i) = self { Double(i) } else { nil } }
        public var text: String? { if case .text(let v) = self { v } else { nil } }
    }

    public func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let m = err.map { String(cString: $0) } ?? "failed"
            sqlite3_free(err)
            throw HealthStoreError.sqlite(m)
        }
    }

    @discardableResult
    public func query(_ sql: String, _ args: [Value] = []) throws -> [[Value]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HealthStoreError.sqlite(String(cString: sqlite3_errmsg(db)) + " in: " + sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() {
            let n = Int32(i + 1)
            switch a {
            case .null: sqlite3_bind_null(stmt, n)
            case .int(let v): sqlite3_bind_int64(stmt, n, v)
            case .real(let v): sqlite3_bind_double(stmt, n, v)
            case .text(let v): sqlite3_bind_text(stmt, n, v, -1, transient)
            case .blob(let v): v.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, n, $0.baseAddress, Int32(v.count), transient) }
            }
        }
        var rows: [[Value]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw HealthStoreError.sqlite(String(cString: sqlite3_errmsg(db)) + " in: " + sql) }
            var row: [Value] = []
            for c in 0..<sqlite3_column_count(stmt) {
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(stmt, c)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(stmt, c))))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, c))
                    let p = sqlite3_column_blob(stmt, c)
                    row.append(.blob(n > 0 && p != nil ? [UInt8](UnsafeRawBufferPointer(start: p, count: n)) : []))
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }

    public var changes: Int { Int(sqlite3_changes(db)) }
    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }

    public func queryWithColumns(_ sql: String, _ args: [Value] = []) throws -> (columns: [String], rows: [[Value]]) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HealthStoreError.sqlite(String(cString: sqlite3_errmsg(db)) + " in: " + sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() {
            let n = Int32(i + 1)
            switch a {
            case .null: sqlite3_bind_null(stmt, n)
            case .int(let v): sqlite3_bind_int64(stmt, n, v)
            case .real(let v): sqlite3_bind_double(stmt, n, v)
            case .text(let v): sqlite3_bind_text(stmt, n, v, -1, transient)
            case .blob(let v): v.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, n, $0.baseAddress, Int32(v.count), transient) }
            }
        }
        var columns: [String] = []
        for c in 0..<sqlite3_column_count(stmt) {
            columns.append(sqlite3_column_name(stmt, c).map { String(cString: $0) } ?? "")
        }
        var rows: [[Value]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw HealthStoreError.sqlite(String(cString: sqlite3_errmsg(db)) + " in: " + sql) }
            var row: [Value] = []
            for c in 0..<sqlite3_column_count(stmt) {
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(stmt, c)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(stmt, c))))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, c))
                    let p = sqlite3_column_blob(stmt, c)
                    row.append(.blob(n > 0 && p != nil ? [UInt8](UnsafeRawBufferPointer(start: p, count: n)) : []))
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return (columns, rows)
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let r = try body()
            try execute("COMMIT")
            return r
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}

public struct HealthStore {
    public let directory: String
    public var unprotectedPath: String { directory + "/healthdb.sqlite" }
    public var protectedPath: String { directory + "/healthdb_secure.sqlite" }

    public init(dev: String) { directory = dev + "/data/Library/Health" }
    public init(directory: String) { self.directory = directory }

    public var exists: Bool { FileManager.default.fileExists(atPath: unprotectedPath) }

    public static func storeTime(_ d: Date) -> Double { d.timeIntervalSinceReferenceDate }

    @discardableResult
    public func backup(into backups: String, reason: String, keep: Int = 5, now: Date = Date()) throws -> String {
        let fm = FileManager.default
        guard exists else { throw HealthStoreError.noStore(directory) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        var target = backups + "/" + f.string(from: now) + "-" + reason
        var n = 2
        while fm.fileExists(atPath: target) { target = backups + "/" + f.string(from: now) + "-" + reason + "-\(n)"; n += 1 }
        try fm.createDirectory(atPath: target, withIntermediateDirectories: true)
        for name in try fm.contentsOfDirectory(atPath: directory) where name.hasPrefix("healthdb") {
            try fm.copyItem(atPath: directory + "/" + name, toPath: target + "/" + name)
        }
        let all = ((try? fm.contentsOfDirectory(atPath: backups)) ?? []).sorted()
        for old in all.dropLast(keep) { try? fm.removeItem(atPath: backups + "/" + old) }
        return target
    }

    public struct AuthorizationRow: Equatable, Sendable {
        public let sourceID: Int
        public let objectType: Int
        public let status: Int
        public let request: Int
    }

    func open() throws -> SQLiteDatabase {
        guard exists else { throw HealthStoreError.noStore(directory) }
        return try SQLiteDatabase(path: unprotectedPath)
    }

    static let sourcesOf = """
        SELECT s.ROWID FROM sources s JOIN logical_sources l ON s.logical_source_id = l.ROWID WHERE l.bundle_id = ?
        """

    public func sourceIDs(bundleID: String) throws -> [Int] {
        try open().query(Self.sourcesOf, [.text(bundleID)]).compactMap { $0.first?.int }
    }

    public func authorizationRows(bundleID: String) throws -> [AuthorizationRow] {
        try open().query("SELECT source_id, object_type, status, request FROM authorization WHERE source_id IN (\(Self.sourcesOf)) "
                         + "ORDER BY source_id, object_type", [.text(bundleID)])
            .map { AuthorizationRow(sourceID: $0[0].int ?? 0, objectType: $0[1].int ?? 0, status: $0[2].int ?? 0, request: $0[3].int ?? 0) }
    }

    public struct GrantResult: Equatable, Sendable, CustomStringConvertible {
        public var rows = 0
        public var shared = 0, readOnly = 0, denied = 0
        public var changed = 0

        public var description: String {
            rows == 0 ? "no authorization rows yet (the app has not asked for access on this device)"
                : "\(rows) types: \(shared) share and read, \(readOnly) read only, \(denied) denied (\(changed) changed)"
        }
    }

    @discardableResult
    public func grant(bundleID: String, now: Date = Date()) throws -> GrantResult {
        let db = try open()
        return try db.transaction {
            let t = SQLiteDatabase.Value.real(Self.storeTime(now))
            var changed = 0
            try db.query("UPDATE authorization SET status = ?, date_modified = ? WHERE source_id IN (\(Self.sourcesOf)) AND request = ? AND status != ?",
                         [.int(Int64(HealthAuthorizationCode.sharingAuthorized)), t, .text(bundleID),
                          .int(Int64(HealthAuthorizationCode.sharePresented)), .int(Int64(HealthAuthorizationCode.sharingAuthorized))])
            changed += db.changes
            try db.query("UPDATE authorization SET status = ?, date_modified = ? WHERE source_id IN (\(Self.sourcesOf)) AND request = ? AND status != ?",
                         [.int(Int64(HealthAuthorizationCode.sharingDenied)), t, .text(bundleID),
                          .int(Int64(HealthAuthorizationCode.readPresented)), .int(Int64(HealthAuthorizationCode.sharingDenied))])
            changed += db.changes
            var r = try summary(db, bundleID)
            r.changed = changed
            return r
        }
    }

    @discardableResult
    public func revoke(bundleID: String, now: Date = Date()) throws -> GrantResult {
        let db = try open()
        return try db.transaction {
            try db.query("UPDATE authorization SET status = ?, date_modified = ? WHERE source_id IN (\(Self.sourcesOf)) AND status != ?",
                         [.int(Int64(HealthAuthorizationCode.bothDenied)), .real(Self.storeTime(now)), .text(bundleID),
                          .int(Int64(HealthAuthorizationCode.bothDenied))])
            var r = try summary(db, bundleID)
            r.changed = db.changes
            return r
        }
    }

    func summary(_ db: SQLiteDatabase, _ bundleID: String) throws -> GrantResult {
        var r = GrantResult()
        for row in try db.query("SELECT status FROM authorization WHERE source_id IN (\(Self.sourcesOf))", [.text(bundleID)]) {
            r.rows += 1
            switch row[0].int {
            case HealthAuthorizationCode.sharingAuthorized: r.shared += 1
            case HealthAuthorizationCode.sharingDenied: r.readOnly += 1
            case HealthAuthorizationCode.bothDenied: r.denied += 1
            default: break
            }
        }
        return r
    }
}
