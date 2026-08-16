import XCTest
@testable import AllInGentleKit

@MainActor
final class ProjectDetailViewModelTests: XCTestCase {

    func testExactMatchShowsMemoriesAndDocuments() async {
        let projectPath = "/tmp/my-project"
        let memory = MemoryObservation(
            id: "m1",
            title: "Memory",
            content: "Content",
            project: projectPath,
            tags: []
        )
        let document = OpenSpecScanner.Document(
            id: "\(projectPath)/spec.md", path: "\(projectPath)/spec.md", title: "Spec")

        let engram = EngramSearchProviderStub(results: [memory], observationsResults: [memory])
        let scanner = StubOpenSpecScanning(documents: [document])
        let viewModel = ProjectDetailViewModel(engram: engram, scanner: scanner)

        viewModel.load(projectPath: projectPath)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.memories.count, 1)
        XCTAssertEqual(viewModel.memories.first?.title, "Memory")
        XCTAssertFalse(viewModel.usedFallbackSearch)
        XCTAssertEqual(viewModel.documents.count, 1)
        XCTAssertEqual(viewModel.documents.first?.title, "Spec")

        let observationsProject = await engram.capturedObservationsProject
        let observationsLimit = await engram.capturedObservationsLimit
        let searchQuery = await engram.capturedSearchQuery
        XCTAssertEqual(
            observationsProject,
            projectPath,
            "R5: exact match must fetch server-side observations for the project"
        )
        XCTAssertEqual(observationsLimit, 200, "exact match must request 200 observations")
        XCTAssertNil(searchQuery, "R7: exact match must never issue a search with q=\"\"")
    }

    func testFallbackSearchWhenExactMatchEmpty() async {
        let projectPath = "/tmp/my-project"
        let memory = MemoryObservation(
            id: "m1",
            title: "my-project note",
            content: "Body",
            project: nil,
            tags: []
        )

        let engram = EngramSearchProviderStub(results: [memory])
        let scanner = StubOpenSpecScanning()
        let viewModel = ProjectDetailViewModel(engram: engram, scanner: scanner)

        viewModel.load(projectPath: projectPath)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.memories.count, 1)
        XCTAssertTrue(viewModel.usedFallbackSearch)

        let observationsProject = await engram.capturedObservationsProject
        let observationsLimit = await engram.capturedObservationsLimit
        let searchQuery = await engram.capturedSearchQuery
        XCTAssertEqual(observationsProject, projectPath)
        XCTAssertEqual(observationsLimit, 200)
        XCTAssertEqual(searchQuery, "my-project", "fallback must search by project name, never an empty q")
    }

    func testObservationsFallbackFiltersClientSideForSearchOnlyProvider() async {
        struct SearchOnlyProvider: EngramSearchProvider {
            func search(query: String, limit: Int) async throws -> [MemoryObservation] {
                [
                    MemoryObservation(id: "a", title: "A", content: "", project: "alpha", tags: []),
                    MemoryObservation(id: "b", title: "B", content: "", project: "/projects/beta", tags: [])
                ]
            }
        }
        let scanner = StubOpenSpecScanning()
        let viewModel = ProjectDetailViewModel(engram: SearchOnlyProvider(), scanner: scanner)

        viewModel.load(projectPath: "/projects/alpha")
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.memories.map(\.id), ["a"])
        XCTAssertFalse(
            viewModel.usedFallbackSearch,
            "R8: extension-default observations must apply the client-side filter, no fallback needed"
        )
    }

    func testCancelsInFlightLoadWhenSelectionChanges() async {
        let memoryA = MemoryObservation(id: "a", title: "A", content: "", project: "/projectA", tags: [])
        let engram = EngramSearchProviderStub(results: [memoryA], sleepDuration: .milliseconds(500))
        let scanner = StubOpenSpecScanning()
        let viewModel = ProjectDetailViewModel(engram: engram, scanner: scanner)

        viewModel.load(projectPath: "/projectA")
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.load(projectPath: "/projectB")
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertTrue(viewModel.memories.isEmpty)
    }

    func testErrorsDegradeToErrorMessage() async {
        let engram = EngramSearchProviderStub(thrownError: AllInGentleError.sourceUnavailable("offline"))
        let scanner = StubOpenSpecScanning()
        let viewModel = ProjectDetailViewModel(engram: engram, scanner: scanner)

        viewModel.load(projectPath: "/tmp/project")
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.memories.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
