import XCTest
import Darwin
@testable import AllInGentleKit

final class OpenSpecScannerTests: XCTestCase {
    private var tempDirectory: URL!
    private let scanner = OpenSpecScanner()

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openspec-scanner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    private func write(_ content: String, to relativePath: String) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func write(_ data: Data, to relativePath: String) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    /// The scanner's enumerator returns realpath-canonical URLs (e.g. `/var` →
    /// `/private/var`), which Foundation path APIs preserve. Compute expectations
    /// with the same canonicalization the enumerator applies.
    private func realPath(of url: URL) -> String {
        let path = url.path
        guard let resolved = path.withCString({ realpath($0, nil) }) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - scan() — R-3.1 / R-3.2 / R-3.3 (S-3.1, S-3.2, S-3.3)

    func testScanReturnsOnlyMarkdownDocumentsSortedByPath() async throws {
        try write("# Alpha", to: "a.md")
        try write("not markdown", to: "b.txt")
        try write("# Hidden", to: ".hidden.md")
        try write("plain text", to: "no-title.md")
        try write("# Charlie", to: "sub/c.md")

        let documents = try await scanner.scan(root: tempDirectory.path)

        let root = URL(fileURLWithPath: realPath(of: tempDirectory))
        XCTAssertEqual(
            documents.map(\.path),
            [
                root.appendingPathComponent("a.md").path,
                root.appendingPathComponent("no-title.md").path,
                root.appendingPathComponent("sub/c.md").path,
            ]
        )
        XCTAssertEqual(documents.map(\.title), ["Alpha", nil, "Charlie"])
    }

    func testScanExtractsFirstMarkdownHeadingOnly() async throws {
        try write("# First\n\n## Subheading\n#Alpha\n# Second", to: "multi.md")

        let documents = try await scanner.scan(root: tempDirectory.path)

        XCTAssertEqual(documents.map(\.title), ["First"])
    }

    func testScanReturnsNilTitleWhenHeadingAbsent() async throws {
        try write("plain text without a heading", to: "no-title.md")

        let documents = try await scanner.scan(root: tempDirectory.path)

        XCTAssertEqual(documents.map(\.title), [nil])
    }

    func testScanThrowsSourceUnavailableWhenRootMissing() async throws {
        let missingRoot = tempDirectory.appendingPathComponent("does-not-exist")

        do {
            _ = try await scanner.scan(root: missingRoot.path)
            XCTFail("Expected sourceUnavailable for missing root")
        } catch {
            guard case AllInGentleError.sourceUnavailable = error else {
                return XCTFail("Expected sourceUnavailable, got \(error)")
            }
        }
    }

    // MARK: - projects() — R-3.5 (S-3.4)

    func testProjectsRecordsParentDirectoriesDeduplicatedAndSorted() async throws {
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("apps/one/openspec"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("apps/two/openspec"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("apps/three/OpenSpec"),
            withIntermediateDirectories: true
        )
        try write("not a directory", to: "apps/four/openspec.txt")
        try write("file named openspec", to: "apps/five/openspec")

        let projects = try await scanner.projects(root: tempDirectory.path)

        let root = URL(fileURLWithPath: realPath(of: tempDirectory))
        XCTAssertEqual(
            projects.map(\.path),
            [
                root.appendingPathComponent("apps/one").path,
                root.appendingPathComponent("apps/three").path,
                root.appendingPathComponent("apps/two").path,
            ]
        )
        XCTAssertEqual(projects.map(\.name), ["one", "three", "two"])
        XCTAssertTrue(projects.allSatisfy { $0.source == .openspec })
    }

    func testProjectsThrowsSourceUnavailableWhenRootMissing() async throws {
        let missingRoot = tempDirectory.appendingPathComponent("does-not-exist")

        do {
            _ = try await scanner.projects(root: missingRoot.path)
            XCTFail("Expected sourceUnavailable for missing root")
        } catch {
            guard case AllInGentleError.sourceUnavailable = error else {
                return XCTFail("Expected sourceUnavailable, got \(error)")
            }
        }
    }

    // MARK: - preview() — R-3.6 (pin current behavior; no production change)

    func testPreviewReturnsFileText() async throws {
        try write("# Alpha", to: "a.md")

        let text = try await scanner.preview(at: tempDirectory.appendingPathComponent("a.md").path)

        XCTAssertEqual(text, "# Alpha")
    }

    func testPreviewReturnsEmptyStringForEmptyFile() async throws {
        try write("", to: "empty.md")

        let text = try await scanner.preview(at: tempDirectory.appendingPathComponent("empty.md").path)

        XCTAssertEqual(text, "")
    }

    func testPreviewThrowsSourceUnavailableForUndecodableBytes() async throws {
        try write(Data([0xFF, 0xFE]), to: "binary.md")

        do {
            _ = try await scanner.preview(at: tempDirectory.appendingPathComponent("binary.md").path)
            XCTFail("Expected sourceUnavailable for undecodable bytes")
        } catch {
            guard case AllInGentleError.sourceUnavailable = error else {
                return XCTFail("Expected sourceUnavailable, got \(error)")
            }
        }
    }
}
