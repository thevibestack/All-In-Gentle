import Foundation
import Observation

@MainActor
@Observable
public final class ProjectDetailViewModel {
    public private(set) var memories: [MemoryObservation] = []
    public private(set) var documents: [OpenSpecScanner.Document] = []
    public private(set) var isLoading: Bool = false
    public private(set) var usedFallbackSearch: Bool = false
    public var errorMessage: String?

    private let engram: any EngramSearchProvider
    private let scanner: any OpenSpecScanning
    private var loadTask: Task<Void, Never>?

    public init(
        engram: any EngramSearchProvider = EngramClient(),
        scanner: any OpenSpecScanning = OpenSpecScanner()
    ) {
        self.engram = engram
        self.scanner = scanner
    }

    public func load(projectPath: String) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(projectPath: projectPath)
        }
    }

    private func performLoad(projectPath: String) async {
        let normalized = ProjectPathNormalizer.normalize(projectPath)
        isLoading = true
        errorMessage = nil
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            try Task.checkCancellation()
            let exact = try await engram.observations(project: normalized, limit: 200)
            try Task.checkCancellation()

            if !exact.isEmpty {
                memories = exact
                usedFallbackSearch = false
            } else {
                memories = try await fallbackMemories(for: normalized)
                usedFallbackSearch = true
            }

            try Task.checkCancellation()
            documents = try await scanner.scan(root: normalized)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func fallbackMemories(for projectPath: String) async throws -> [MemoryObservation] {
        let projectName = (projectPath as NSString).lastPathComponent
        let raw = try await engram.search(query: projectName, limit: 50, project: nil)
        let nameQuery = projectName.localizedLowercase
        let pathQuery = projectPath.localizedLowercase
        return raw.filter { observation in
            let title = observation.title.localizedLowercase
            let content = observation.content.localizedLowercase
            let project = observation.project?.localizedLowercase ?? ""
            return title.contains(nameQuery) || content.contains(nameQuery) || title.contains(pathQuery)
                || content.contains(pathQuery) || project.contains(nameQuery)
        }
    }
}
