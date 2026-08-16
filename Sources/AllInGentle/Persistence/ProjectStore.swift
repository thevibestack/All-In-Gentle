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
/// normalized path, keeping filesystem keys safe and deterministic. The store
/// is a thin facade over ``FileBackedJSONStore``.
public actor ProjectStore: ProjectStoring {
    private let store: FileBackedJSONStore<StoredProject>

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
        let resolvedDirectory =
            directory
            ?? Self.resolveDefaultDirectory(
                fileManager: fileManager,
                subdirectory: "Projects"
            )
        self.store = FileBackedJSONStore(
            directory: resolvedDirectory,
            subdirectory: "Projects",
            filenameStrategy: { id in
                let hash = SHA256.hash(data: Data(id.utf8))
                let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
                return "\(hex).json"
            },
            sortComparator: { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            touch: { $0.lastSeen = Date() }
        )
    }

    private static func resolveDefaultDirectory(fileManager: FileManager, subdirectory: String) -> URL {
        FileBackedJSONStore<StoredProject>.resolveDefaultDirectory(
            urls: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask),
            fallback: fileManager.homeDirectoryForCurrentUser,
            subdirectory: subdirectory
        )
    }

    /// Loads every project from the store directory, name-ascending.
    public func loadAll() async throws -> [StoredProject] {
        try await store.loadAll()
    }

    /// Saves a project to disk as atomic JSON.
    public func save(_ project: StoredProject) async throws {
        _ = try await store.save(project)
    }

    /// Deletes a project from disk by its normalized-path id.
    public func delete(id: String) async throws {
        try await store.delete(id: id)
    }
}
