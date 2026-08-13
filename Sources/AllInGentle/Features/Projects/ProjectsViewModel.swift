import Foundation
import Observation

public protocol ProjectSourceProvider: Sendable {
    func projects() async throws -> [Project]
}

extension EngramClient: ProjectSourceProvider {}

extension OpenCodeClient: ProjectSourceProvider {}

public struct CodeGraphProjectSource: ProjectSourceProvider {
    private let client: CodeGraphClient
    private let root: String

    public init(client: CodeGraphClient, root: String) {
        self.client = client
        self.root = root
    }

    public func projects() async throws -> [Project] {
        try await client.projects(at: root)
    }
}

public struct OpenSpecProjectSource: ProjectSourceProvider {
    private let scanner: OpenSpecScanner
    private let root: String

    public init(scanner: OpenSpecScanner, root: String) {
        self.scanner = scanner
        self.root = root
    }

    public func projects() async throws -> [Project] {
        try await scanner.projects(root: root)
    }
}

public struct ProjectItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let sources: [Project.Source]
}

@MainActor
@Observable
public final class ProjectsViewModel {
    public private(set) var items: [ProjectItem] = []
    public private(set) var isLoading: Bool = false
    public var errorMessage: String?
    public var searchQuery: String = ""

    public var filteredItems: [ProjectItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.name.localizedStandardContains(query) ||
                item.path.localizedStandardContains(query)
        }
    }

    private let providers: [any ProjectSourceProvider]

    public init(providers: [any ProjectSourceProvider]) {
        self.providers = providers
    }

    public convenience init(
        engramBaseURL: URL = URL(string: "http://127.0.0.1:7437")!,
        openCodeDBPath: String? = nil,
        codegraphRoot: String? = nil,
        openspecRoot: String? = nil
    ) {
        let openCodePath = Self.resolvePath(openCodeDBPath) ?? Self.defaultOpenCodeDBPath()
        let graphRoot = Self.resolvePath(codegraphRoot) ?? Self.defaultHomePath()
        let specRoot = Self.resolvePath(openspecRoot) ?? Self.defaultHomePath()

        let engram = EngramClient(baseURL: engramBaseURL)
        let openCode = OpenCodeClient(dbPath: openCodePath)
        let codegraph = CodeGraphClient()
        let scanner = OpenSpecScanner()

        self.init(providers: [
            engram,
            openCode,
            CodeGraphProjectSource(client: codegraph, root: graphRoot),
            OpenSpecProjectSource(scanner: scanner, root: specRoot)
        ])
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }

        var allProjects: [Project] = []
        var messages: [String] = []

        await withTaskGroup(of: LoadResult.self) { group in
            for provider in providers {
                group.addTask { await Self.fetchProjects(from: provider) }
            }
            for await result in group {
                switch result {
                case .success(let projects):
                    allProjects.append(contentsOf: projects)
                case .failure(let message):
                    messages.append(message)
                }
            }
        }

        items = merge(allProjects)
        errorMessage = items.isEmpty && !messages.isEmpty ? messages.joined(separator: "\n") : nil
    }

    private func merge(_ projects: [Project]) -> [ProjectItem] {
        let grouped = Dictionary(grouping: projects, by: \.path)
        return grouped.map { path, projects in
            let openCode = projects.first { $0.source == .opencode }
            let name: String
            if let openCode, !openCode.name.isEmpty {
                name = openCode.name
            } else {
                name = (path as NSString).lastPathComponent
            }
            let sourceSet = Set(projects.map(\.source))
            let sources = Project.Source.allCases.filter { sourceSet.contains($0) }
            return ProjectItem(id: path, path: path, name: name, sources: sources)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func fetchProjects(from provider: any ProjectSourceProvider) async -> LoadResult {
        do {
            return .success(try await provider.projects())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func resolvePath(_ path: String?) -> String? {
        guard let path else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    private static func defaultHomePath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static func defaultOpenCodeDBPath() -> String {
        defaultHomePath() + "/.local/share/opencode/opencode.db"
    }
}

private enum LoadResult: Sendable {
    case success([Project])
    case failure(String)
}
