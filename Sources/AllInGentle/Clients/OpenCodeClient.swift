import Foundation
import SQLite3

public struct TokenCursor: Codable, Hashable, Sendable {
    public let timeUpdated: Double
    public let id: String

    public init(timeUpdated: Double, id: String) {
        self.timeUpdated = timeUpdated
        self.id = id
    }
}

internal enum SQLiteValue: Sendable {
    case int64(Int64)
    case double(Double)
    case text(String)
}

internal enum SQLiteColumn: Sendable, Equatable {
    case null
    case int64(Int64)
    case double(Double)
    case text(String)
}

internal struct SQLiteRow: Sendable {
    let columns: [SQLiteColumn]

    subscript(index: Int) -> SQLiteColumn {
        columns[index]
    }

    func isNull(_ index: Int) -> Bool {
        columns[index] == .null
    }

    func text(_ index: Int) -> String? {
        if case .text(let value) = columns[index] { return value }
        return nil
    }

    func int64(_ index: Int) -> Int64? {
        if case .int64(let value) = columns[index] { return value }
        return nil
    }

    func double(_ index: Int) -> Double? {
        switch columns[index] {
        case .int64(let value): return Double(value)
        case .double(let value): return value
        case .null, .text: return nil
        }
    }

    /// Epoch-millis accessor: INTEGER/REAL native; numeric TEXT fallback for legacy rows.
    func millis(_ index: Int) -> Double? {
        switch columns[index] {
        case .int64(let value): return Double(value)
        case .double(let value): return value
        case .text(let value): return Double(value)
        case .null: return nil
        }
    }
}

public actor OpenCodeClient {
    public let dbPath: String

    public init(dbPath: String) {
        self.dbPath = dbPath
    }

    public func projects() async throws -> [Project] {
        let rows = try executeReadOnly(
            """
            SELECT id, name, worktree, time_updated
            FROM project
            ORDER BY name
            """
        )
        return rows.compactMap { row in
            guard let id = row.text(0), let path = row.text(2) else { return nil }
            let rawName = row.text(1)
            let name = rawName?.isEmpty == false ? rawName! : (path as NSString).lastPathComponent
            let date = row.millis(3).map { millisToDate($0) }
            return Project(
                id: id,
                name: name,
                path: path,
                source: .opencode,
                lastModified: date
            )
        }
    }

    public func sessionSummaries() async throws -> [SessionSummary] {
        let rows = try executeReadOnly(
            """
            SELECT id, project_id, title, cost, tokens_input, tokens_output, time_updated
            FROM session
            ORDER BY time_updated DESC
            """
        )
        return rows.compactMap { row in
            guard let fields = parseSessionFields(row) else { return nil }
            return SessionSummary(
                id: fields.id,
                project: fields.project,
                sessionName: fields.title,
                messageCount: 0,
                totalTokens: fields.input + fields.output,
                estimatedCost: fields.cost,
                latestDate: fields.date
            )
        }
    }

    public func tokenUsage(limit: Int = 100) async throws -> [TokenUsage] {
        let clamped = max(0, limit)
        let rows = try executeReadOnly(
            """
            SELECT id, project_id, title, cost, tokens_input, tokens_output, time_updated
            FROM session
            ORDER BY time_updated DESC
            LIMIT ?
            """,
            bind: [.int64(Int64(clamped))]
        )
        return rows.compactMap { row in
            guard let fields = parseSessionFields(row) else { return nil }
            return TokenUsage(
                id: fields.id,
                project: fields.project,
                session: fields.title,
                promptTokens: fields.input,
                completionTokens: fields.output,
                estimatedCost: fields.cost,
                timestamp: fields.date,
                rawTimeUpdated: fields.timeUpdated
            )
        }
    }

    public func tokenUsagePage(after cursor: TokenCursor? = nil, limit: Int = 50) async throws -> [TokenUsage] {
        let clamped = max(0, limit)
        let base = """
            SELECT id, project_id, title, cost, tokens_input, tokens_output, time_updated
            FROM session
            """
        let sql: String
        let bind: [SQLiteValue]
        if let cursor {
            guard cursor.timeUpdated.isFinite else {
                throw AllInGentleError.sourceUnavailable("non-finite cursor")
            }
            sql =
                base + "\n" + """
                    WHERE (time_updated < ? OR (time_updated = ? AND id < ?))
                    ORDER BY time_updated DESC, id DESC
                    LIMIT ?
                    """
            bind = [
                .double(cursor.timeUpdated),
                .double(cursor.timeUpdated),
                .text(cursor.id),
                .int64(Int64(clamped)),
            ]
        } else {
            sql = base + " ORDER BY time_updated DESC, id DESC LIMIT ?"
            bind = [.int64(Int64(clamped))]
        }
        let rows = try executeReadOnly(sql, bind: bind)
        return rows.compactMap { row in
            guard let fields = parseSessionFields(row) else { return nil }
            return TokenUsage(
                id: fields.id,
                project: fields.project,
                session: fields.title,
                promptTokens: fields.input,
                completionTokens: fields.output,
                estimatedCost: fields.cost,
                timestamp: fields.date,
                rawTimeUpdated: fields.timeUpdated
            )
        }
    }

    internal func executeReadOnly(_ sql: String, bind values: [SQLiteValue] = []) throws -> [SQLiteRow] {
        try validateReadOnly(sql)

        var db: OpaquePointer?
        let openStatus = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)
        guard openStatus == SQLITE_OK, let db else {
            throw AllInGentleError.sourceUnavailable("Unable to open OpenCode database read-only: \(openStatus)")
        }
        defer { sqlite3_close_v2(db) }

        sqlite3_exec(db, "PRAGMA query_only=1;", nil, nil, nil)

        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw AllInGentleError.sourceUnavailable("Unable to prepare query: \(prepareStatus)")
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            let status: Int32
            switch value {
            case .int64(let intValue):
                status = sqlite3_bind_int64(statement, Int32(index + 1), intValue)
            case .double(let doubleValue):
                status = sqlite3_bind_double(statement, Int32(index + 1), doubleValue)
            case .text(let textValue):
                status = sqlite3_bind_text(statement, Int32(index + 1), textValue, -1, SQLITE_TRANSIENT)
            }
            guard status == SQLITE_OK else {
                throw AllInGentleError.sourceUnavailable("Unable to bind parameter \(index + 1): \(status)")
            }
        }

        let columnCount = Int(sqlite3_column_count(statement))
        var results: [SQLiteRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var columns: [SQLiteColumn] = []
            columns.reserveCapacity(columnCount)
            for i in 0..<columnCount {
                let index = Int32(i)
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    columns.append(.int64(sqlite3_column_int64(statement, index)))
                case SQLITE_FLOAT:
                    columns.append(.double(sqlite3_column_double(statement, index)))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, index) {
                        columns.append(.text(String(cString: text)))
                    } else {
                        columns.append(.null)
                    }
                default:
                    columns.append(.null)
                }
            }
            results.append(SQLiteRow(columns: columns))
        }
        return results
    }

    private func validateReadOnly(_ sql: String) throws {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.hasPrefix("SELECT") else {
            throw AllInGentleError.readOnlyViolation
        }
    }

    /// Applies the single drop-row policy shared by `sessionSummaries`, `tokenUsage`, and
    /// `tokenUsagePage`: NULL or unparseable identity/time_updated drops the row; NULL
    /// display numerics become 0; unparseable display numerics drop the row; the date is
    /// always derived from `time_updated`, never fabricated.
    private func parseSessionFields(
        _ row: SQLiteRow
    ) -> (
        id: String, project: String, title: String, cost: Double, input: Int, output: Int, timeUpdated: Double,
        date: Date
    )? {
        guard let id = row.text(0),
            let project = row.text(1),
            let title = row.text(2),
            let timeUpdated = row.millis(6),
            timeUpdated.isFinite,
            let cost = displayDouble(row[3]),
            let input = displayInt(row[4]),
            let output = displayInt(row[5])
        else { return nil }
        return (id, project, title, cost, input, output, timeUpdated, millisToDate(timeUpdated))
    }

    private func displayDouble(_ column: SQLiteColumn) -> Double? {
        switch column {
        case .null: return 0
        case .int64(let value): return Double(value)
        case .double(let value): return value
        case .text(let value): return Double(value)
        }
    }

    private func displayInt(_ column: SQLiteColumn) -> Int? {
        switch column {
        case .null: return 0
        case .int64(let value): return Int(value)
        case .double(let value): return Int(value)
        case .text(let value): return Int(value)
        }
    }

    private func millisToDate(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000.0)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
