import Foundation
import XCTest
@testable import AllInGentleKit
import AllInGentleTestSupport

@MainActor
final class WikiViewModelTests: XCTestCase {

    func testLoadDocumentsFiltersByProjectPathPrefix() async throws {
        let projectPath = "/projects/wiki"
        let docs = [
            OpenSpecScanner.Document(id: "\(projectPath)/spec.md", path: "\(projectPath)/spec.md", title: "Spec"),
            OpenSpecScanner.Document(id: "\(projectPath)/readme.md", path: "\(projectPath)/readme.md", title: "Readme"),
            OpenSpecScanner.Document(id: "/other/project.md", path: "/other/project.md", title: "Other"),
        ]
        let scanner = StubOpenSpecScanning(documents: docs)
        let viewModel = WikiViewModel(
            engram: StubEngramSearchProvider(),
            scanner: scanner
        )

        viewModel.loadDocuments(forProjectPath: projectPath)
        let loaded = await waitUntil {
            viewModel.documents.count == 2
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.documents.count, 2)
        XCTAssertTrue(viewModel.documents.allSatisfy { $0.path.hasPrefix(projectPath) })
    }

    func testLoadDocumentsWithNilProjectPathClearsState() async throws {
        let scanner = StubOpenSpecScanning(
            documents: [OpenSpecScanner.Document(id: "/tmp/spec.md", path: "/tmp/spec.md", title: "Spec")],
            preview: "preview"
        )
        let viewModel = WikiViewModel(
            engram: StubEngramSearchProvider(),
            scanner: scanner
        )
        viewModel.loadDocuments(forProjectPath: "/tmp")
        let loaded = await waitUntil {
            viewModel.documents.count == 1
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.documents.count, 1)

        viewModel.selectDocument(viewModel.documents[0])
        let previewLoaded = await waitUntil {
            !viewModel.previewText.isEmpty
        }
        XCTAssertTrue(previewLoaded)
        XCTAssertFalse(viewModel.previewText.isEmpty)

        viewModel.loadDocuments(forProjectPath: nil)
        let cleared = await waitUntil {
            viewModel.documents.isEmpty && viewModel.previewText.isEmpty
        }
        XCTAssertTrue(cleared)

        XCTAssertTrue(viewModel.documents.isEmpty)
        XCTAssertNil(viewModel.selectedDocument)
        XCTAssertTrue(viewModel.previewText.isEmpty)
    }

    func testSearchPassesProjectPathToEngram() async throws {
        let observation = MemoryObservation(
            id: "m1",
            title: "Match",
            content: "Content",
            project: "p1",
            tags: []
        )
        let engram = StubEngramSearchProvider()
        engram.results = [observation]
        let viewModel = WikiViewModel(
            engram: engram,
            scanner: StubOpenSpecScanning()
        )
        viewModel.selectedProjectPath = "/projects/p1"

        viewModel.searchQuery = "match"
        let filled = await waitUntil {
            !viewModel.results.isEmpty
        }
        XCTAssertTrue(filled)

        XCTAssertEqual(engram.lastQuery, "match")
        XCTAssertEqual(engram.lastProject, "/projects/p1")
        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertEqual(viewModel.results.first?.id, "m1")
    }

    func testSearchWithZeroDebounceExecutesImmediately() async throws {
        let observation = MemoryObservation(
            id: "m1",
            title: "Match",
            content: "Content",
            project: "p1",
            tags: []
        )
        let engram = StubEngramSearchProvider()
        engram.results = [observation]
        let viewModel = WikiViewModel(
            engram: engram,
            scanner: StubOpenSpecScanning(),
            searchDebounce: .zero
        )
        viewModel.selectedProjectPath = "/projects/p1"

        viewModel.searchQuery = "match"
        let filled = await waitUntil(timeout: .milliseconds(200)) {
            !viewModel.results.isEmpty
        }

        XCTAssertTrue(filled, "search must run without debounce delay when searchDebounce is .zero")
        XCTAssertEqual(viewModel.results.first?.id, "m1")
        XCTAssertEqual(engram.lastQuery, "match")
    }

    func testSearchSkippedWhenNoProjectSelected() async throws {
        let engram = StubEngramSearchProvider()
        engram.results = [MemoryObservation(id: "m1", title: "Match", content: "Content", project: nil, tags: [])]
        let viewModel = WikiViewModel(
            engram: engram,
            scanner: StubOpenSpecScanning()
        )

        viewModel.searchQuery = "match"

        // No project selected: the search must be skipped. Bounded poll to
        // surface any delayed (incorrect) search within the debounce window.
        let searched = await waitUntil(timeout: .milliseconds(350)) {
            engram.lastQuery != nil
        }
        XCTAssertFalse(searched)

        XCTAssertNil(engram.lastQuery)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testSearchResultsScopedToProjectByDefaultProvider() async throws {
        struct FilteringStub: EngramSearchProvider {
            func search(query: String, limit: Int) async throws -> [MemoryObservation] {
                [
                    MemoryObservation(id: "a", title: "A", content: "", project: "/projects/alpha", tags: []),
                    MemoryObservation(id: "b", title: "B", content: "", project: "/projects/beta", tags: []),
                    MemoryObservation(id: "c", title: "C", content: "", project: nil, tags: []),
                ]
            }
        }
        let viewModel = WikiViewModel(
            engram: FilteringStub(),
            scanner: StubOpenSpecScanning()
        )
        viewModel.selectedProjectPath = "/projects/alpha"

        viewModel.searchQuery = "query"
        let filled = await waitUntil {
            !viewModel.results.isEmpty
        }
        XCTAssertTrue(filled)

        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertEqual(viewModel.results.first?.id, "a")
    }
}
