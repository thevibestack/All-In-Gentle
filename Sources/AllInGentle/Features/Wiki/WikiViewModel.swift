import Foundation
import Observation

public protocol EngramSearchProvider: Sendable {
    func search(query: String, limit: Int) async throws -> [MemoryObservation]
    func search(query: String, limit: Int, project: String?) async throws -> [MemoryObservation]
}

extension EngramSearchProvider {
    public func search(query: String, limit: Int, project: String?) async throws -> [MemoryObservation] {
        let results = try await search(query: query, limit: limit)
        if let project {
            return results.filter { $0.project == project }
        }
        return results
    }
}

extension EngramClient: EngramSearchProvider {}

public protocol OpenSpecScanning: Sendable {
    func scan(root: String) async throws -> [OpenSpecScanner.Document]
    func preview(at path: String) async throws -> String
}

extension OpenSpecScanner: OpenSpecScanning {}

@MainActor
@Observable
public final class WikiViewModel {
    public var searchQuery: String = "" {
        didSet { scheduleSearch() }
    }

    public var selectedProjectPath: String? = nil {
        didSet { scheduleSearch() }
    }

    public private(set) var results: [MemoryObservation] = []
    public private(set) var documents: [OpenSpecScanner.Document] = []
    public var selectedDocument: OpenSpecScanner.Document?
    public private(set) var previewText: String = ""
    public private(set) var isSearching: Bool = false
    public private(set) var isLoadingDocuments: Bool = false
    public var errorMessage: String?

    private let engram: any EngramSearchProvider
    private let scanner: any OpenSpecScanning
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    public init(
        engram: any EngramSearchProvider,
        scanner: any OpenSpecScanning
    ) {
        self.engram = engram
        self.scanner = scanner
    }

    public convenience init(
        engramBaseURL: URL = URL(string: "http://127.0.0.1:7437")!
    ) {
        self.init(
            engram: EngramClient(baseURL: engramBaseURL),
            scanner: OpenSpecScanner()
        )
    }

    public func loadDocuments() {
        loadDocuments(forProjectPath: selectedProjectPath)
    }

    public func loadDocuments(forProjectPath path: String?) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoadDocuments(forProjectPath: path)
        }
    }

    public func selectDocument(_ document: OpenSpecScanner.Document) {
        selectedDocument = document
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.previewText = try await self.scanner.preview(at: document.path)
            } catch {
                guard !Task.isCancelled else { return }
                self.previewText = ""
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func performLoadDocuments(forProjectPath path: String?) async {
        isLoadingDocuments = true
        errorMessage = nil
        defer { if !Task.isCancelled { isLoadingDocuments = false } }

        documents = []
        selectedDocument = nil
        previewText = ""
        guard let path else { return }

        do {
            try Task.checkCancellation()
            let normalized = ProjectPathNormalizer.normalize(path)
            let scanned = try await scanner.scan(root: normalized)
            try Task.checkCancellation()
            documents = scanned.filter { $0.path.hasPrefix(normalized) }
        } catch {
            guard !Task.isCancelled else { return }
            documents = []
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = selectedProjectPath
        guard !query.isEmpty, project != nil else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            await self.performSearch(query: query, project: project)
        }
    }

    private func performSearch(query: String, project: String?) async {
        defer { isSearching = false }
        do {
            results = try await engram.search(query: query, limit: 50, project: project)
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }
}
