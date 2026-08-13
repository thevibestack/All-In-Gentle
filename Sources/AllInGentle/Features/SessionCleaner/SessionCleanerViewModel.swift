import Foundation
import Observation

/// A grouped view of OpenCode sessions for the Session Cleaner tab.
public struct SessionGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let sessions: [SessionSummary]
    public let totalTokens: Int
    public let totalCost: Double
    public let latestDate: Date

    public init(
        id: String,
        name: String,
        sessions: [SessionSummary],
        totalTokens: Int,
        totalCost: Double,
        latestDate: Date
    ) {
        self.id = id
        self.name = name
        self.sessions = sessions
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.latestDate = latestDate
    }
}

/// View model for the Session Cleaner tab.
///
/// Loads ``SessionSummary`` rows from ``OpenCodeClient``, groups them by project,
/// and derives a readable project name from the OpenCode `project` table.
@MainActor
@Observable
public final class SessionCleanerViewModel {
    public private(set) var groups: [SessionGroup] = []
    public private(set) var isLoading: Bool = false
    public var errorMessage: String?

    private let client: OpenCodeClient

    public init(client: OpenCodeClient) {
        self.client = client
    }

    public convenience init(openCodeDBPath: String? = nil) {
        let path = Self.resolvePath(openCodeDBPath) ?? Self.defaultOpenCodeDBPath()
        self.init(client: OpenCodeClient(dbPath: path))
    }

    /// Internal test initializer that bypasses the database.
    internal init(sessions: [SessionSummary], projects: [Project]) {
        self.client = OpenCodeClient(dbPath: ":memory:")
        let names = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0.name) }
        )
        self.groups = Self.makeGroups(from: sessions, projectNames: names)
    }

    /// Loads sessions and projects concurrently, then groups by project.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let (sessions, projects) = try await fetchSessionsAndProjects()
            let names = Dictionary(
                uniqueKeysWithValues: projects.map { ($0.id, $0.name) }
            )
            groups = Self.makeGroups(from: sessions, projectNames: names)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchSessionsAndProjects() async throws -> (sessions: [SessionSummary], projects: [Project]) {
        try await withThrowingTaskGroup(of: FetchResult.self) { group in
            group.addTask { .sessions(try await self.client.sessionSummaries()) }
            group.addTask { .projects(try await self.client.projects()) }

            var sessions: [SessionSummary] = []
            var projects: [Project] = []
            for try await result in group {
                switch result {
                case .sessions(let value):
                    sessions = value
                case .projects(let value):
                    projects = value
                }
            }
            return (sessions, projects)
        }
    }

    private static func makeGroups(
        from sessions: [SessionSummary],
        projectNames: [String: String]
    ) -> [SessionGroup] {
        let grouped = Dictionary(grouping: sessions, by: \.project)
        return grouped.map { projectID, sessions in
            let sorted = sessions.sorted { $0.latestDate > $1.latestDate }
            let totalTokens = sorted.reduce(0) { $0 + $1.totalTokens }
            let totalCost = sorted.reduce(0) { $0 + $1.estimatedCost }
            let latestDate = sorted.first?.latestDate ?? Date()
            let rawName = projectNames[projectID]
            let displayName = rawName.flatMap { $0.isEmpty ? nil : $0 } ?? projectID
            return SessionGroup(
                id: projectID,
                name: displayName,
                sessions: sorted,
                totalTokens: totalTokens,
                totalCost: totalCost,
                latestDate: latestDate
            )
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func resolvePath(_ path: String?) -> String? {
        guard let path else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    private static func defaultOpenCodeDBPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
            + "/.local/share/opencode/opencode.db"
    }
}

private enum FetchResult: Sendable {
    case sessions([SessionSummary])
    case projects([Project])
}
