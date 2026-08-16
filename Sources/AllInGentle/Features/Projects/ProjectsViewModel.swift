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

    public var selection: ProjectItem? = nil {
        didSet {
            onSelectionChange?(selection?.path)
        }
    }

    public var onSelectionChange: ((String?) -> Void)?

    public var filteredItems: [ProjectItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.name.localizedStandardContains(query) || item.path.localizedStandardContains(query)
        }
    }

    private let providers: [any ProjectSourceProvider]
    private let store: any ProjectStoring
    private var initialSelectedPath: String?

    public init(
        providers: [any ProjectSourceProvider],
        store: any ProjectStoring = ProjectStore(),
        initialSelectedPath: String? = nil,
        onSelectionChange: ((String?) -> Void)? = nil
    ) {
        self.providers = providers
        self.store = store
        self.initialSelectedPath = initialSelectedPath
        self.onSelectionChange = onSelectionChange
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
            OpenSpecProjectSource(scanner: scanner, root: specRoot),
        ])
    }

    public func load() async {
        await load(initialSelectedPath: initialSelectedPath)
    }

    public func load(initialSelectedPath: String?) async {
        isLoading = true
        defer { isLoading = false }
        self.initialSelectedPath = initialSelectedPath

        do {
            let stored = try await store.loadAll()
            var merged = stored.map { ProjectItem(id: $0.id, path: $0.path, name: $0.name, sources: $0.sources) }
            var messages: [String] = []

            await withTaskGroup(of: LoadResult.self) { group in
                for provider in providers {
                    group.addTask { await Self.fetchProjects(from: provider) }
                }
                for await result in group {
                    switch result {
                    case .success(let projects):
                        merged = merge(providers: projects, into: merged)
                    case .failure(let message):
                        messages.append(message)
                    }
                }
            }

            items = merged
            for item in items {
                try? await store.save(
                    StoredProject(id: item.id, name: item.name, path: item.path, sources: item.sources))
            }
            restoreSelectionIfNeeded()
            errorMessage = items.isEmpty && !messages.isEmpty ? messages.joined(separator: "\n") : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreSelectionIfNeeded() {
        guard let path = initialSelectedPath else { return }
        let normalized = ProjectPathNormalizer.normalize(path)
        selection = items.first { ProjectPathNormalizer.normalize($0.path) == normalized }
        initialSelectedPath = nil
    }

    private func merge(providers projects: [Project], into existing: [ProjectItem]) -> [ProjectItem] {
        var byPath: [String: (name: String, sources: Set<Project.Source>)] = [:]
        for item in existing {
            byPath[item.path] = (name: item.name, sources: Set(item.sources))
        }
        for project in projects {
            let path = ProjectPathNormalizer.normalize(project.path)
            var entry = byPath[path] ?? (name: (path as NSString).lastPathComponent, sources: [])
            if project.source == .opencode, !project.name.isEmpty {
                entry.name = project.name
            }
            entry.sources.insert(project.source)
            byPath[path] = entry
        }
        return byPath.map { path, entry in
            let sources = Project.Source.allCases.filter { entry.sources.contains($0) }
            return ProjectItem(id: path, path: path, name: entry.name, sources: sources)
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
