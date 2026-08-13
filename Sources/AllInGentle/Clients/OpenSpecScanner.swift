import Foundation

public actor OpenSpecScanner {

    public struct Document: Identifiable, Codable, Hashable, Sendable {
        public let id: String
        public let path: String
        public let title: String?

        public init(id: String, path: String, title: String? = nil) {
            self.id = id
            self.path = path
            self.title = title
        }
    }

    public init() {}

    public func scan(root: String) async throws -> [Document] {
        let url = URL(fileURLWithPath: root)
        let manager = FileManager.default
        guard manager.fileExists(atPath: root) else {
            throw AllInGentleError.sourceUnavailable("OpenSpec root does not exist: \(root)")
        }
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AllInGentleError.sourceUnavailable("Unable to enumerate OpenSpec root: \(root)")
        }

        var documents: [Document] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let path = fileURL.path
            let title = await firstMarkdownTitle(at: fileURL)
            documents.append(Document(id: path, path: path, title: title))
        }
        return documents.sorted { $0.path < $1.path }
    }

    public func projects(root: String) async throws -> [Project] {
        let url = URL(fileURLWithPath: root)
        let manager = FileManager.default
        guard manager.fileExists(atPath: root) else {
            throw AllInGentleError.sourceUnavailable("OpenSpec root does not exist: \(root)")
        }
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AllInGentleError.sourceUnavailable("Unable to enumerate OpenSpec root: \(root)")
        }

        var paths: Set<String> = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.lastPathComponent.lowercased() == "openspec" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let parentPath = fileURL.deletingLastPathComponent().path
            paths.insert(parentPath)
        }

        return paths.sorted().map { path in
            Project(
                id: path,
                name: (path as NSString).lastPathComponent,
                path: path,
                source: .openspec,
                lastModified: nil
            )
        }
    }

    public func preview(at path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AllInGentleError.sourceUnavailable("Unable to decode OpenSpec document: \(path)")
        }
        return text
    }

    private func firstMarkdownTitle(at url: URL) async -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return nil
    }
}
