import Foundation
import CryptoKit

public protocol ProjectStoring: Sendable {
    func loadAll() async throws -> [StoredProject]
    func save(_ project: StoredProject) async throws
    func delete(id: String) async throws
}

/// File-system persistence for ``StoredProject`` records.
///
/// ``ProjectStore`` reads and writes projects as JSON in the app’s
/// Application Support directory under the `Projects` subdirectory. Each
/// project is stored in a file named after the SHA-256 hash of its
/// normalized path, keeping filesystem keys safe and deterministic.
public actor ProjectStore: ProjectStoring {
    private let fileManager: FileManager
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a store rooted at the given directory.
    ///
    /// - Parameters:
    ///   - directory: The directory in which project JSON files are stored.
    ///     Defaults to `~/Library/Application Support/All-In-Gentle/Projects`.
    ///   - fileManager: The file manager to use for disk operations.
    public init(
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        if let directory {
            self.directory = directory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("All-In-Gentle/Projects", isDirectory: true)
        }
    }

    /// Loads every project from the store directory.
    public func loadAll() async throws -> [StoredProject] {
        try ensureDirectoryExists()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        .filter { $0.pathExtension == "json" }

        var projects: [StoredProject] = []
        for url in urls {
            if let data = fileManager.contents(atPath: url.path),
               let project = try? decoder.decode(StoredProject.self, from: data) {
                projects.append(project)
            }
        }
        return projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Saves a project to disk as atomic JSON.
    public func save(_ project: StoredProject) async throws {
        try ensureDirectoryExists()
        var project = project
        project.lastSeen = Date()
        let url = fileURL(for: project.id)
        let data = try encoder.encode(project)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Deletes a project from disk by its normalized-path id.
    public func delete(id: String) async throws {
        try fileManager.removeItem(at: fileURL(for: id))
    }

    // MARK: - Helpers

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent(filename(for: id), isDirectory: false)
    }

    private func filename(for id: String) -> String {
        let hash = SHA256.hash(data: Data(id.utf8))
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return "\(hex).json"
    }

    private func ensureDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { return }
            throw AllInGentleError.persistenceFailure("Project store path exists but is not a directory: \(directory.path)")
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
