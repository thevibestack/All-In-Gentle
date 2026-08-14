import XCTest
@testable import AllInGentleKit

actor StubEngramSearchProviderActor: EngramSearchProvider {
    private var results: [MemoryObservation]
    private var sleepDuration: Duration
    private(set) var capturedProjectFilter: String?
    private var thrownError: Error?

    init(
        results: [MemoryObservation] = [],
        sleepDuration: Duration = .seconds(0),
        thrownError: Error? = nil
    ) {
        self.results = results
        self.sleepDuration = sleepDuration
        self.thrownError = thrownError
    }

    func search(query: String, limit: Int) async throws -> [MemoryObservation] {
        try await Task.sleep(for: sleepDuration)
        if let thrownError { throw thrownError }
        return results
    }

    func search(query: String, limit: Int, project: String?) async throws -> [MemoryObservation] {
        capturedProjectFilter = project
        let all = try await search(query: query, limit: limit)
        if let project {
            return all.filter { $0.project == project }
        }
        return all
    }
}

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
        let document = OpenSpecScanner.Document(id: "\(projectPath)/spec.md", path: "\(projectPath)/spec.md", title: "Spec")

        let engram = StubEngramSearchProviderActor(results: [memory])
        let scanner = StubOpenSpecScanning(documents: [document])
        let viewModel = ProjectDetailViewModel(engram: engram, scanner: scanner)

        viewModel.load(projectPath: projectPath)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.memories.count, 1)
        XCTAssertEqual(viewModel.memories.first?.title, "Memory")
        XCTAssertFalse(viewModel.usedFallbackSearch)
        XCTAssertEqual(viewModel.documents.count, 1)
        XCTAssertEqual(viewModel.documents.first?.title, "Spec")
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

        let engram = StubEngramSearchProviderActor(results: [memory])
        let scanner = StubOpenSpecScanning()
        let viewModel = ProjectDetailViewModel(engram: engram, scanner: scanner)

        viewModel.load(projectPath: projectPath)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.memories.count, 1)
        XCTAssertTrue(viewModel.usedFallbackSearch)
    }

    func testCancelsInFlightLoadWhenSelectionChanges() async {
        let memoryA = MemoryObservation(id: "a", title: "A", content: "", project: "/projectA", tags: [])
        let engram = StubEngramSearchProviderActor(results: [memoryA], sleepDuration: .milliseconds(500))
        let scanner = StubOpenSpecScanning()
        let viewModel = ProjectDetailViewModel(engram: engram, scanner: scanner)

        viewModel.load(projectPath: "/projectA")
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.load(projectPath: "/projectB")
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertTrue(viewModel.memories.isEmpty)
    }

    func testErrorsDegradeToErrorMessage() async {
        let engram = StubEngramSearchProviderActor(thrownError: AllInGentleError.sourceUnavailable("offline"))
        let scanner = StubOpenSpecScanning()
        let viewModel = ProjectDetailViewModel(engram: engram, scanner: scanner)

        viewModel.load(projectPath: "/tmp/project")
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.memories.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
