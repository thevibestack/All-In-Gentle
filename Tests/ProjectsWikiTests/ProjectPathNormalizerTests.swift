import XCTest
@testable import AllInGentleKit

final class ProjectPathNormalizerTests: XCTestCase {
    func testExpandsTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(ProjectPathNormalizer.normalize("~/dev"), "\(home)/dev")
    }

    func testTrimsTrailingSlash() {
        XCTAssertEqual(ProjectPathNormalizer.normalize("/tmp/foo/"), "/tmp/foo")
    }

    func testKeepsRootPath() {
        XCTAssertEqual(ProjectPathNormalizer.normalize("/"), "/")
    }

    func testStandardizesRedundantComponents() {
        XCTAssertEqual(ProjectPathNormalizer.normalize("/tmp/./bar/../foo"), "/tmp/foo")
    }

    func testResolvesSymlinks() throws {
        let temp = FileManager.default.temporaryDirectory
        let real = temp.appendingPathComponent("normalizer-real-\(UUID().uuidString)")
        let link = temp.appendingPathComponent("normalizer-link-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let normalized = ProjectPathNormalizer.normalize(link.path)
        XCTAssertEqual(normalized, real.path)

        try? FileManager.default.removeItem(at: real)
        try? FileManager.default.removeItem(at: link)
    }

    func testEquivalentPathsNormalizeToSameKey() throws {
        let temp = FileManager.default.temporaryDirectory
        let real = temp.appendingPathComponent("normalizer-dedupe-\(UUID().uuidString)")
        let link = temp.appendingPathComponent("normalizer-dedupe-link-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let a = ProjectPathNormalizer.normalize(link.path + "/")
        let b = ProjectPathNormalizer.normalize(real.path)
        XCTAssertEqual(a, b)

        try? FileManager.default.removeItem(at: real)
        try? FileManager.default.removeItem(at: link)
    }
}
