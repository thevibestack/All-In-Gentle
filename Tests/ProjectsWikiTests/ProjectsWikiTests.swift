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
