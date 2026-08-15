import Foundation
import XCTest
@testable import AllInGentleKit

/// Tests the generic ``FileBackedJSONStore`` composition actor: roundtrip,
/// delete, injected filename strategy, corrupt-file tolerance, sort comparator,
/// touch closure, and home-dir directory fallback.
@MainActor
final class FileBackedJSONStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-backed-store-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    private struct Record: Codable, Identifiable, Sendable, Equatable {
        let id: String
        var name: String
        var updatedAt: Date
    }

    private func makeStore(
        touch: @escaping @Sendable (inout Record) -> Void = { $0.updatedAt = Date() }
    ) -> FileBackedJSONStore<Record> {
        FileBackedJSONStore(
            directory: tempDirectory,
            subdirectory: "Records",
            filenameStrategy: { "\($0).json" },
            sortComparator: { $0.updatedAt > $1.updatedAt },
            touch: touch
        )
    }

    func testSaveAndLoadRoundtrip() async throws {
        let store = makeStore()
        let record = Record(id: "1", name: "First", updatedAt: Date(timeIntervalSince1970: 100))
        let saved = try await store.save(record)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "1")
        XCTAssertEqual(loaded.first?.name, "First")
        XCTAssertGreaterThanOrEqual(saved.updatedAt, record.updatedAt, "touch must stamp the save date")
    }

    func testDeleteRemovesItem() async throws {
        let store = makeStore()
        try await store.save(Record(id: "1", name: "First", updatedAt: Date()))

        try await store.delete(id: "1")

        let loaded = try await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testFilenameStrategyIsHonored() async throws {
        let store = makeStore()

        try await store.save(Record(id: "my-id", name: "First", updatedAt: Date()))

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(files, ["my-id.json"])
    }

    func testCorruptFileIsToleratedAndGoodFilesStillLoad() async throws {
        let store = makeStore()
        try await store.save(Record(id: "good", name: "First", updatedAt: Date()))
        try Data("not json".utf8).write(to: tempDirectory.appendingPathComponent("corrupt.json"))

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "good")
    }

    func testSortComparatorIsApplied() async throws {
        let store = makeStore(touch: { _ in })

        try await store.save(Record(id: "old", name: "Old", updatedAt: Date(timeIntervalSince1970: 100)))
        try await store.save(Record(id: "new", name: "New", updatedAt: Date(timeIntervalSince1970: 200)))

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.map(\.id), ["new", "old"])
    }

    func testResolveDefaultDirectoryUsesFirstURLWhenPresent() {
        let first = URL(fileURLWithPath: "/tmp/first")
        let second = URL(fileURLWithPath: "/tmp/second")

        let resolved = FileBackedJSONStore<Record>.resolveDefaultDirectory(
            urls: [first, second],
            fallback: URL(fileURLWithPath: "/tmp/fallback"),
            subdirectory: "Sessions"
        )

        XCTAssertEqual(resolved.path, "/tmp/first/All-In-Gentle/Sessions")
    }

    func testResolveDefaultDirectoryFallsBackToHomeWhenURLsEmpty() {
        let fallback = URL(fileURLWithPath: "/Users/tester")

        let resolved = FileBackedJSONStore<Record>.resolveDefaultDirectory(
            urls: [],
            fallback: fallback,
            subdirectory: "Projects"
        )

        XCTAssertEqual(resolved.path, "/Users/tester/Library/Application Support/All-In-Gentle/Projects")
    }
}
