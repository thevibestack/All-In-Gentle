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
            guard let id = row[0], let path = row[2] else { return nil }
            let rawName = row[1]
            let name = rawName?.isEmpty == false ? rawName! : (path as NSString).lastPathComponent
            let date = row[3].flatMap { parseMillis($0) }
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
            guard let id = row[0],
                let project = row[1],
                let title = row[2]
            else { return nil }
            let cost = row[3].flatMap { Double($0) } ?? 0
            let input = row[4].flatMap { Int($0) } ?? 0
            let output = row[5].flatMap { Int($0) } ?? 0
            let date = row[6].flatMap { parseMillis($0) } ?? Date()
            return SessionSummary(
                id: id,
                project: project,
                sessionName: title,
                messageCount: 0,
                totalTokens: input + output,
                estimatedCost: cost,
                latestDate: date
            )
        }
    }

    public func tokenUsage(limit: Int = 100) async throws -> [TokenUsage] {
        let rows = try executeReadOnly(
            """
            SELECT id, project_id, title, cost, tokens_input, tokens_output, time_updated
            FROM session
            ORDER BY time_updated DESC
            LIMIT \(limit)
            """
        )
        return rows.compactMap { row in
            guard let id = row[0],
                let project = row[1],
                let session = row[2]
            else { return nil }
            let cost = row[3].flatMap { Double($0) } ?? 0
            let input = row[4].flatMap { Int($0) } ?? 0
            let output = row[5].flatMap { Int($0) } ?? 0
            let timeUpdated = row[6].flatMap { Double($0) }
            let date = row[6].flatMap { parseMillis($0) } ?? Date()
            return TokenUsage(
                id: id,
                project: project,
                session: session,
                promptTokens: input,
                completionTokens: output,
                estimatedCost: cost,
                timestamp: date,
                rawTimeUpdated: timeUpdated
            )
        }
    }

    public func tokenUsagePage(after cursor: TokenCursor? = nil, limit: Int = 50) async throws -> [TokenUsage] {
        let base = """
            SELECT id, project_id, title, cost, tokens_input, tokens_output, time_updated
            FROM session
            """
        let sql: String
        if let cursor {
            let escapedID = escapeSQLString(cursor.id)
            sql =
                base + """
                    WHERE (time_updated < \(cursor.timeUpdated) OR (time_updated = \(cursor.timeUpdated) AND id < '\(escapedID)'))
                    ORDER BY time_updated DESC, id DESC
                    LIMIT \(limit)
                    """
        } else {
            sql = base + " ORDER BY time_updated DESC, id DESC LIMIT \(limit)"
        }
        let rows = try executeReadOnly(sql)
        return rows.compactMap { row in
            guard let id = row[0],
                let project = row[1],
                let session = row[2],
                let timeUpdatedString = row[6],
                let timeUpdated = Double(timeUpdatedString)
            else { return nil }
            let cost = row[3].flatMap { Double($0) } ?? 0
            let input = row[4].flatMap { Int($0) } ?? 0
            let output = row[5].flatMap { Int($0) } ?? 0
            let date = parseMillis(timeUpdatedString) ?? Date()
            return TokenUsage(
                id: id,
                project: project,
                session: session,
                promptTokens: input,
                completionTokens: output,
                estimatedCost: cost,
                timestamp: date,
                rawTimeUpdated: timeUpdated
            )
        }
    }

    private func escapeSQLString(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    internal func executeReadOnly(_ sql: String) throws -> [[String?]] {
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

        let columnCount = Int(sqlite3_column_count(statement))
        var results: [[String?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row = [String?](repeating: nil, count: columnCount)
            for i in 0..<columnCount {
                if let text = sqlite3_column_text(statement, Int32(i)) {
                    let cString = UnsafeRawPointer(text).assumingMemoryBound(to: Int8.self)
                    row[i] = String(cString: cString)
                }
            }
            results.append(row)
        }
        return results
    }

    private func validateReadOnly(_ sql: String) throws {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.hasPrefix("SELECT") else {
            throw AllInGentleError.readOnlyViolation
        }
    }

    private func parseMillis(_ text: String) -> Date? {
        guard let value = Double(text) else { return nil }
        return Date(timeIntervalSince1970: value / 1000.0)
    }
}
