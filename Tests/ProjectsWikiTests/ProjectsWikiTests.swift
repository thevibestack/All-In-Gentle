import Foundation
import XCTest
@testable import AllInGentleKit
import AllInGentleTestSupport

struct StubProjectSourceProvider: ProjectSourceProvider {
    var projects: [Project] = []

    func projects() async throws -> [Project] {
        projects
    }
}

actor EngramSearchProviderStub: EngramSearchProvider {
    private var results: [MemoryObservation]
    private var observationsResults: [MemoryObservation]
    private var sleepDuration: Duration
    private var thrownError: Error?
    private(set) var lastQuery: String?
    private(set) var lastProject: String?
    private(set) var capturedProjectFilter: String?
    private(set) var capturedSearchQuery: String?
    private(set) var capturedObservationsProject: String?
    private(set) var capturedObservationsLimit: Int?

    init(
        results: [MemoryObservation] = [],
        observationsResults: [MemoryObservation] = [],
        sleepDuration: Duration = .seconds(0),
        thrownError: Error? = nil
    ) {
        self.results = results
        self.observationsResults = observationsResults
        self.sleepDuration = sleepDuration
        self.thrownError = thrownError
    }

    func search(query: String, limit: Int) async throws -> [MemoryObservation] {
        try await Task.sleep(for: sleepDuration)
        if let thrownError { throw thrownError }
        lastQuery = query
        return results
    }

    func search(query: String, limit: Int, project: String?) async throws -> [MemoryObservation] {
        capturedProjectFilter = project
        capturedSearchQuery = query
        lastQuery = query
        lastProject = project
        try await Task.sleep(for: sleepDuration)
        if let thrownError { throw thrownError }
        if let project {
            return results.filter { $0.project == project }
        }
        return results
    }

    func observations(project: String, limit: Int) async throws -> [MemoryObservation] {
        capturedObservationsProject = project
        capturedObservationsLimit = limit
        try await Task.sleep(for: sleepDuration)
        if let thrownError { throw thrownError }
        return observationsResults
    }
}

struct StubOpenSpecScanning: OpenSpecScanning {
    var documents: [OpenSpecScanner.Document] = []
    var preview: String = ""

    func scan(root: String) async throws -> [OpenSpecScanner.Document] {
        documents
    }

    func preview(at path: String) async throws -> String {
        preview
    }
}

@MainActor
final class ProjectsWikiTests: XCTestCase {

    func testProjectsViewModelMergesSourcesAndDerivesDisplayName() async {
        let openCode = Project(
            id: "p1",
            name: "",
            path: "/tmp/My Project",
            source: .opencode
        )
        let codeGraph = Project(
            id: "p1",
            name: "Ignored",
            path: "/tmp/My Project",
            source: .codegraph
        )
        let providers: [any ProjectSourceProvider] = [
            StubProjectSourceProvider(projects: [openCode]),
            StubProjectSourceProvider(projects: [codeGraph]),
        ]
        let viewModel = ProjectsViewModel(providers: providers, store: StubProjectStoring())
        await viewModel.load()

        XCTAssertEqual(viewModel.items.count, 1)
        let item = viewModel.items.first!
        XCTAssertEqual(item.name, "My Project")
        XCTAssertEqual(item.path, "/tmp/My Project")
        XCTAssertEqual(Set(item.sources), [.opencode, .codegraph])
    }

    func testProjectsViewModelUsesOpenCodeNameWhenPresent() async {
        let openCode = Project(
            id: "p1",
            name: "Custom Name",
            path: "/tmp/My Project",
            source: .opencode
        )
        let codeGraph = Project(
            id: "p1",
            name: "Other",
            path: "/tmp/My Project",
            source: .codegraph
        )
        let providers: [any ProjectSourceProvider] = [
            StubProjectSourceProvider(projects: [openCode]),
            StubProjectSourceProvider(projects: [codeGraph]),
        ]
        let viewModel = ProjectsViewModel(providers: providers, store: StubProjectStoring())
        await viewModel.load()

        XCTAssertEqual(viewModel.items.first?.name, "Custom Name")
    }

    func testProjectsViewModelFiltersBySearchQuery() async {
        let alpha = Project(id: "a", name: "Alpha", path: "/tmp/alpha", source: .codegraph)
        let beta = Project(id: "b", name: "Beta", path: "/tmp/beta", source: .openspec)
        let viewModel = ProjectsViewModel(providers: [
            StubProjectSourceProvider(projects: [alpha, beta])
        ])
        await viewModel.load()

        viewModel.searchQuery = "alp"
        XCTAssertEqual(viewModel.filteredItems.count, 1)
        XCTAssertEqual(viewModel.filteredItems.first?.name, "alpha")

        viewModel.searchQuery = "beta"
        XCTAssertEqual(viewModel.filteredItems.count, 1)
        XCTAssertEqual(viewModel.filteredItems.first?.name, "beta")

        viewModel.searchQuery = ""
        XCTAssertEqual(viewModel.filteredItems.count, 2)
    }

    func testWikiViewModelDebouncesSearch() async throws {
        let observation = MemoryObservation(
            id: "m1",
            title: "Found",
            content: "Content",
            project: "/projects/p1",
            tags: []
        )
        let engram = EngramSearchProviderStub(results: [observation])
        let scanner = StubOpenSpecScanning()
        let viewModel = WikiViewModel(
            engram: engram,
            scanner: scanner
        )
        viewModel.selectedProjectPath = "/projects/p1"

        viewModel.searchQuery = "hello"
        XCTAssertEqual(viewModel.results.count, 0)
        XCTAssertTrue(viewModel.isSearching)

        // Default 300ms debounce: poll until the debounced search lands.
        let filled = await waitUntil {
            !viewModel.results.isEmpty
        }
        XCTAssertTrue(filled)
        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertEqual(viewModel.results.first?.title, "Found")
        let lastProject = await engram.lastProject
        XCTAssertEqual(lastProject, "/projects/p1")
        XCTAssertFalse(viewModel.isSearching)
    }

    func testWikiViewModelInjectedDebounceShowsMidDebounceState() async throws {
        let observation = MemoryObservation(
            id: "m1",
            title: "Found",
            content: "Content",
            project: "/projects/p1",
            tags: []
        )
        let engram = EngramSearchProviderStub(results: [observation])
        let scanner = StubOpenSpecScanning()
        let viewModel = WikiViewModel(
            engram: engram,
            scanner: scanner,
            searchDebounce: .milliseconds(100)
        )
        viewModel.selectedProjectPath = "/projects/p1"

        viewModel.searchQuery = "hello"

        // Mid-debounce: query submitted but results not filled yet.
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertTrue(viewModel.isSearching)

        let filled = await waitUntil {
            !viewModel.results.isEmpty
        }
        XCTAssertTrue(filled)
        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testWikiViewModelLoadsPreview() async throws {
        let document = OpenSpecScanner.Document(
            id: "/tmp/spec.md",
            path: "/tmp/spec.md",
            title: "Spec"
        )
        let scanner = StubOpenSpecScanning(
            documents: [document],
            preview: "# OpenSpec Preview"
        )
        let viewModel = WikiViewModel(
            engram: EngramSearchProviderStub(),
            scanner: scanner
        )

        viewModel.loadDocuments(forProjectPath: "/tmp")
        let loaded = await waitUntil {
            viewModel.documents.count == 1
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.documents.count, 1)

        viewModel.selectDocument(document)
        XCTAssertEqual(viewModel.selectedDocument, document)

        let previewLoaded = await waitUntil {
            viewModel.previewText == "# OpenSpec Preview"
        }
        XCTAssertTrue(previewLoaded)
        XCTAssertEqual(viewModel.previewText, "# OpenSpec Preview")
    }
}
