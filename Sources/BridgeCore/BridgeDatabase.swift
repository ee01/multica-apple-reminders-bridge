import Foundation
import CSQLite

public enum BridgeDatabaseError: Error, CustomStringConvertible {
    case open(String)
    case sqlite(String)

    public var description: String {
        switch self {
        case .open(let message): return "Could not open bridge database: \(message)"
        case .sqlite(let message): return "SQLite error: \(message)"
        }
    }
}

public final class BridgeDatabase: BridgePersistence, @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            db = nil
            throw BridgeDatabaseError.open(message)
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try exec("PRAGMA busy_timeout=5000;")
    }

    deinit { sqlite3_close(db) }

    public func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS issue_observation (
          issue_id TEXT PRIMARY KEY,
          issue_key TEXT NOT NULL,
          status_name TEXT NOT NULL,
          status_category TEXT NOT NULL,
          review_generation INTEGER NOT NULL DEFAULT 0,
          latest_run_id TEXT,
          latest_run_status TEXT,
          payload_hash TEXT,
          observed_updated_at REAL,
          first_blocked_at REAL,
          updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reminder_projection (
          id TEXT PRIMARY KEY,
          issue_id TEXT NOT NULL,
          issue_key TEXT NOT NULL,
          review_generation INTEGER NOT NULL,
          apple_calendar_item_id TEXT,
          apple_external_id TEXT,
          projection_state TEXT NOT NULL,
          user_acknowledged INTEGER NOT NULL DEFAULT 0,
          payload_hash TEXT,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          UNIQUE(issue_id, review_generation)
        );
        CREATE INDEX IF NOT EXISTS idx_projection_active ON reminder_projection(projection_state, issue_id);
        CREATE TABLE IF NOT EXISTS bridge_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        """)
    }

    public func observation(issueID: String) throws -> IssueObservation? {
        try queryOne("SELECT issue_id,issue_key,status_name,status_category,review_generation,latest_run_id,latest_run_status,payload_hash,observed_updated_at,first_blocked_at,updated_at FROM issue_observation WHERE issue_id=?", bind: { stmt in
            self.bind(issueID, at: 1, stmt: stmt)
        }, map: observationFromRow)
    }

    public func upsertObservation(_ o: IssueObservation) throws {
        try execute("""
        INSERT INTO issue_observation(issue_id,issue_key,status_name,status_category,review_generation,latest_run_id,latest_run_status,payload_hash,observed_updated_at,first_blocked_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(issue_id) DO UPDATE SET
          issue_key=excluded.issue_key,status_name=excluded.status_name,status_category=excluded.status_category,
          review_generation=excluded.review_generation,latest_run_id=excluded.latest_run_id,latest_run_status=excluded.latest_run_status,
          payload_hash=excluded.payload_hash,observed_updated_at=excluded.observed_updated_at,first_blocked_at=excluded.first_blocked_at,updated_at=excluded.updated_at
        """) { stmt in
            bind(o.issueID, at: 1, stmt: stmt); bind(o.issueKey, at: 2, stmt: stmt); bind(o.statusName, at: 3, stmt: stmt); bind(o.statusCategory.rawValue, at: 4, stmt: stmt)
            sqlite3_bind_int64(stmt, 5, Int64(o.reviewGeneration)); bind(o.latestRunID, at: 6, stmt: stmt); bind(o.latestRunStatus?.rawValue, at: 7, stmt: stmt); bind(o.payloadHash, at: 8, stmt: stmt)
            bindDate(o.observedUpdatedAt, at: 9, stmt: stmt); bindDate(o.firstBlockedAt, at: 10, stmt: stmt); bindDate(o.updatedAt, at: 11, stmt: stmt)
        }
    }

    public func projection(issueID: String, reviewGeneration: Int) throws -> ReminderProjection? {
        try queryOne("SELECT id,issue_id,issue_key,review_generation,apple_calendar_item_id,apple_external_id,projection_state,user_acknowledged,payload_hash,created_at,updated_at FROM reminder_projection WHERE issue_id=? AND review_generation=?", bind: { stmt in
            self.bind(issueID, at: 1, stmt: stmt); sqlite3_bind_int64(stmt, 2, Int64(reviewGeneration))
        }, map: projectionFromRow)
    }

    public func activeProjections(issueID: String) throws -> [ReminderProjection] {
        try query("SELECT id,issue_id,issue_key,review_generation,apple_calendar_item_id,apple_external_id,projection_state,user_acknowledged,payload_hash,created_at,updated_at FROM reminder_projection WHERE issue_id=? AND projection_state IN ('active','pending_retry')", bind: { stmt in
            self.bind(issueID, at: 1, stmt: stmt)
        }, map: projectionFromRow)
    }

    public func activeProjections() throws -> [ReminderProjection] {
        try query("SELECT id,issue_id,issue_key,review_generation,apple_calendar_item_id,apple_external_id,projection_state,user_acknowledged,payload_hash,created_at,updated_at FROM reminder_projection WHERE projection_state IN ('active','pending_retry')", bind: nil, map: projectionFromRow)
    }

    public func upsertProjection(_ p: ReminderProjection) throws {
        try execute("""
        INSERT INTO reminder_projection(id,issue_id,issue_key,review_generation,apple_calendar_item_id,apple_external_id,projection_state,user_acknowledged,payload_hash,created_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(issue_id,review_generation) DO UPDATE SET
          apple_calendar_item_id=excluded.apple_calendar_item_id,apple_external_id=excluded.apple_external_id,
          projection_state=excluded.projection_state,user_acknowledged=excluded.user_acknowledged,payload_hash=excluded.payload_hash,updated_at=excluded.updated_at
        """) { stmt in
            bind(p.id, at: 1, stmt: stmt); bind(p.issueID, at: 2, stmt: stmt); bind(p.issueKey, at: 3, stmt: stmt); sqlite3_bind_int64(stmt, 4, Int64(p.reviewGeneration))
            bind(p.receipt?.calendarItemIdentifier, at: 5, stmt: stmt); bind(p.receipt?.externalIdentifier, at: 6, stmt: stmt); bind(p.state.rawValue, at: 7, stmt: stmt)
            sqlite3_bind_int(stmt, 8, p.userAcknowledged ? 1 : 0); bind(p.payloadHash, at: 9, stmt: stmt); bindDate(p.createdAt, at: 10, stmt: stmt); bindDate(p.updatedAt, at: 11, stmt: stmt)
        }
    }

    public func setMeta(key: String, value: String) throws {
        try execute("INSERT INTO bridge_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value") { stmt in
            bind(key, at: 1, stmt: stmt); bind(value, at: 2, stmt: stmt)
        }
    }

    public func meta(key: String) throws -> String? {
        let rows: [String] = try query("SELECT value FROM bridge_meta WHERE key=?", bind: { stmt in self.bind(key, at: 1, stmt: stmt) }) { stmt in
            self.text(stmt, column: 0) ?? ""
        }
        return rows.first
    }

    private func exec(_ sql: String) throws {
        try withLock {
            var error: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
                let message = error.map { String(cString: $0) } ?? self.lastError()
                sqlite3_free(error)
                throw BridgeDatabaseError.sqlite(message)
            }
        }
    }

    private func execute(_ sql: String, bind binder: (OpaquePointer) -> Void) throws {
        try withLock {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw BridgeDatabaseError.sqlite(lastError()) }
            defer { sqlite3_finalize(stmt) }
            binder(stmt)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw BridgeDatabaseError.sqlite(lastError()) }
        }
    }

    private func query<T>(_ sql: String, bind binder: ((OpaquePointer) -> Void)?, map: (OpaquePointer) throws -> T) throws -> [T] {
        try withLock {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw BridgeDatabaseError.sqlite(lastError()) }
            defer { sqlite3_finalize(stmt) }
            binder?(stmt)
            var rows: [T] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW { rows.append(try map(stmt)) }
                else if rc == SQLITE_DONE { break }
                else { throw BridgeDatabaseError.sqlite(lastError()) }
            }
            return rows
        }
    }

    private func queryOne<T>(_ sql: String, bind binder: ((OpaquePointer) -> Void)?, map: (OpaquePointer) throws -> T) throws -> T? {
        try query(sql, bind: binder, map: map).first
    }

    private func observationFromRow(_ stmt: OpaquePointer) throws -> IssueObservation {
        IssueObservation(
            issueID: text(stmt, column: 0) ?? "",
            issueKey: text(stmt, column: 1) ?? "",
            statusName: text(stmt, column: 2) ?? "unknown",
            statusCategory: IssueStatusCategory(rawValue: text(stmt, column: 3) ?? "unknown") ?? .unknown,
            reviewGeneration: Int(sqlite3_column_int64(stmt, 4)),
            latestRunID: text(stmt, column: 5),
            latestRunStatus: text(stmt, column: 6).flatMap(RunStatus.init(rawValue:)),
            payloadHash: text(stmt, column: 7),
            observedUpdatedAt: date(stmt, column: 8),
            firstBlockedAt: date(stmt, column: 9),
            updatedAt: date(stmt, column: 10) ?? Date()
        )
    }

    private func projectionFromRow(_ stmt: OpaquePointer) throws -> ReminderProjection {
        let receipt: ReminderReceipt? = {
            let calendar = text(stmt, column: 4)
            let external = text(stmt, column: 5)
            return calendar == nil && external == nil ? nil : ReminderReceipt(calendarItemIdentifier: calendar, externalIdentifier: external)
        }()
        return ReminderProjection(
            id: text(stmt, column: 0) ?? UUID().uuidString,
            issueID: text(stmt, column: 1) ?? "",
            issueKey: text(stmt, column: 2) ?? "",
            reviewGeneration: Int(sqlite3_column_int64(stmt, 3)),
            receipt: receipt,
            state: ReminderProjectionState(rawValue: text(stmt, column: 6) ?? "active") ?? .active,
            userAcknowledged: sqlite3_column_int(stmt, 7) != 0,
            payloadHash: text(stmt, column: 8),
            createdAt: date(stmt, column: 9) ?? Date(),
            updatedAt: date(stmt, column: 10) ?? Date()
        )
    }

    private func bind(_ value: String?, at index: Int32, stmt: OpaquePointer) {
        guard let value else { sqlite3_bind_null(stmt, index); return }
        sqlite3_bind_text(stmt, index, value, -1, Self.transient)
    }

    private func bindDate(_ value: Date?, at index: Int32, stmt: OpaquePointer) {
        guard let value else { sqlite3_bind_null(stmt, index); return }
        sqlite3_bind_double(stmt, index, value.timeIntervalSince1970)
    }

    private func text(_ stmt: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL, let ptr = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: ptr)
    }

    private func date(_ stmt: OpaquePointer, column: Int32) -> Date? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, column))
    }

    private func lastError() -> String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable" }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
}
