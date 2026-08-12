import Foundation
import Observation

public protocol EngramSearchProvider: Sendable {
    func search(query: String, limit: Int) async throws -> [MemoryObservation]
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

    public private(set) var results: [MemoryObservation] = []
    public private(set) var documents: [OpenSpecScanner.Document] = []
    public var selectedDocument: OpenSpecScanner.Document?
    public private(set) var previewText: String = ""
    public private(set) var isSearching: Bool = false
    public var errorMessage: String?

    private let engram: any EngramSearchProvider
    private let scanner: any OpenSpecScanning
    private let openspecRoot: String
    private var searchTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    public init(
        engram: any EngramSearchProvider,
        scanner: any OpenSpecScanning,
        openspecRoot: String
    ) {
        self.engram = engram
        self.scanner = scanner
        self.openspecRoot = openspecRoot
    }

    public convenience init(
        engramBaseURL: URL = URL(string: "http://127.0.0.1:7437")!,
        openspecRoot: String? = nil
    ) {
        let root = Self.resolvePath(openspecRoot) ?? Self.defaultHomePath()
        self.init(
            engram: EngramClient(baseURL: engramBaseURL),
            scanner: OpenSpecScanner(),
            openspecRoot: root
        )
    }

    public func loadDocuments() async {
        do {
            documents = try await scanner.scan(root: openspecRoot)
        } catch {
            documents = []
            errorMessage = error.localizedDescription
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

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            await self.performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        defer { isSearching = false }
        do {
            results = try await engram.search(query: query, limit: 50)
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private static func resolvePath(_ path: String?) -> String? {
        guard let path else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    private static func defaultHomePath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }
}
