import XCTest
@testable import AllInGentleKit

actor StubProjectStoring: ProjectStoring {
    private var projects: [StoredProject] = []
    private var savedProjectsList: [StoredProject] = []

    init(projects: [StoredProject] = []) {
        self.projects = projects
    }

    func setProjects(_ projects: [StoredProject]) {
        self.projects = projects
    }

    func savedProjects() -> [StoredProject] {
        savedProjectsList
    }

    func loadAll() async throws -> [StoredProject] {
        projects
    }

    func save(_ project: StoredProject) async throws {
        savedProjectsList.append(project)
    }

    func delete(id: String) async throws {}
}

@MainActor
final class ProjectsViewModelTests: XCTestCase {

    func testSelectionRestoresByNormalizedPath() async {
        let store = StubProjectStoring(projects: [
            StoredProject(id: "/tmp/my-project", name: "My Project", path: "/tmp/my-project", sources: [.engram])
        ])
        let provider = StubProjectSourceProvider(projects: [])
        var selectedPath: String?

        let viewModel = ProjectsViewModel(
            providers: [provider],
            store: store,
            initialSelectedPath: "/tmp/my-project/",
            onSelectionChange: { selectedPath = $0 }
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.selection?.path, "/tmp/my-project")
        XCTAssertEqual(selectedPath, "/tmp/my-project")
    }

    func testStoreSavesMergedProjects() async {
        let store = StubProjectStoring()
        let project = Project(id: "p1", name: "My Project", path: "/tmp/my-project", source: .opencode)
        let viewModel = ProjectsViewModel(providers: [StubProjectSourceProvider(projects: [project])], store: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.items.count, 1)
        let saved = await store.savedProjects()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.id, "/tmp/my-project")
        XCTAssertEqual(saved.first?.name, "My Project")
    }

    func testSelectionChangeNotifiesAppState() async {
        let store = StubProjectStoring()
        let project = Project(id: "p1", name: "Alpha", path: "/tmp/alpha", source: .codegraph)
        var selectedPath: String?
        let viewModel = ProjectsViewModel(
            providers: [StubProjectSourceProvider(projects: [project])],
            store: store,
            onSelectionChange: { selectedPath = $0 }
        )
        await viewModel.load()

        viewModel.selection = viewModel.items.first

        XCTAssertEqual(selectedPath, "/tmp/alpha")
    }

    func testStoredProjectsAreMergedWithProviderResults() async {
        let store = StubProjectStoring(projects: [
            StoredProject(id: "/tmp/shared", name: "Shared", path: "/tmp/shared", sources: [.engram])
        ])
        let project = Project(id: "p2", name: "OpenCode", path: "/tmp/shared", source: .opencode)
        let viewModel = ProjectsViewModel(providers: [StubProjectSourceProvider(projects: [project])], store: store)

        await viewModel.load()

        let item = viewModel.items.first
        XCTAssertEqual(item?.sources, [.engram, .opencode])
        XCTAssertEqual(item?.name, "OpenCode")
    }
}
