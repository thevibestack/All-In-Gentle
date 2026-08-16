import XCTest
@testable import AllInGentleKit

@MainActor
final class ProjectStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-store-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    private func makeStore() -> ProjectStore {
        ProjectStore(directory: tempDirectory)
    }

    private func makeProject(id: String = "/tmp/my-project") -> StoredProject {
        StoredProject(
            id: id,
            name: "My Project",
            path: id,
            sources: [.opencode, .codegraph]
        )
    }

    func testLoadAllReturnsEmptyWhenDirectoryDoesNotExist() async throws {
        let store = makeStore()
        let projects = try await store.loadAll()
        XCTAssertTrue(projects.isEmpty)
    }

    func testSaveAndLoadProject() async throws {
        let store = makeStore()
        let project = makeProject()
        try await store.save(project)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, project.id)
        XCTAssertEqual(loaded.first?.name, "My Project")
        XCTAssertEqual(loaded.first?.sources, [.opencode, .codegraph])
    }

    func testDeleteProject() async throws {
        let store = makeStore()
        let project = makeProject()
        try await store.save(project)
        try await store.delete(id: project.id)

        let loaded = try await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveUpdatesLastSeen() async throws {
        let store = makeStore()
        let before = Date().addingTimeInterval(-1)
        let project = makeProject()
        try await store.save(project)

        let loaded = try await store.loadAll()
        XCTAssertGreaterThanOrEqual(loaded.first?.lastSeen ?? before, before)
    }

    func testConcurrentSaveAndLoad() async throws {
        let store = makeStore()
        let projects = (0..<10).map { index in
            makeProject(id: "/tmp/project-\(index)")
        }

        await withTaskGroup(of: Void.self) { group in
            for project in projects {
                group.addTask {
                    try? await store.save(project)
                }
            }
        }

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 10)
    }

    func testEquivalentPathsUseSameFile() async throws {
        let temp = FileManager.default.temporaryDirectory
        let real = temp.appendingPathComponent("project-store-real-\(UUID().uuidString)")
        let link = temp.appendingPathComponent("project-store-link-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        defer {
            try? FileManager.default.removeItem(at: real)
            try? FileManager.default.removeItem(at: link)
        }

        let normalized = ProjectPathNormalizer.normalize(link.path)
        let store = makeStore()

        let first = StoredProject(id: normalized, name: "First", path: link.path)
        let second = StoredProject(id: normalized, name: "Second", path: real.path)

        try await store.save(first)
        try await store.save(second)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Second")
    }

    func testAppStatePersistsSelectedProjectPath() {
        let suiteName = "project-store-app-state-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = PreferencesStore(defaults: defaults)
        defer { UserDefaults.standard.removeSuite(named: suiteName) }

        let appState = AppState(preferences: preferences)
        XCTAssertNil(appState.selectedProjectPath)

        appState.selectedProjectPath = "/tmp/selected-project"
        XCTAssertEqual(preferences.string(for: .lastProjectPath), "/tmp/selected-project")

        let restored = AppState(preferences: preferences)
        XCTAssertEqual(restored.selectedProjectPath, "/tmp/selected-project")

        appState.selectedProjectPath = nil
        XCTAssertNil(preferences.string(for: .lastProjectPath))
    }
}
