import Foundation

/// Composable JSON file persistence for small ``Codable`` record sets.
///
/// ``FileBackedJSONStore`` owns directory resolution, encoding/decoding, and
/// atomic file writes so concrete stores only inject their naming, ordering,
/// and touch policies:
///
/// - `filenameStrategy` maps a record id to a JSON filename.
/// - `sortComparator` orders records on load.
/// - `touch` mutates a record just before it is encoded (e.g. stamping a date).
///
/// Decode failures are tolerated per file (`try?`), so a corrupt file never
/// breaks the whole store. Writes are atomic (`[.atomic, .completeFileProtection]`).
public actor FileBackedJSONStore<Item: Codable & Identifiable & Sendable> where Item.ID == String {
    private let directory: URL
    private let subdirectory: String
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let filenameStrategy: @Sendable (String) -> String
    private let sortComparator: @Sendable (Item, Item) -> Bool
    private let touch: @Sendable (inout Item) -> Void

    /// Creates a store rooted at the given directory.
    ///
    /// - Parameters:
    ///   - directory: The directory in which JSON files are stored. Defaults to
    ///     `~/Library/Application Support/All-In-Gentle/<subdirectory>`, falling
    ///     back to the home directory when Application Support cannot be resolved.
    ///   - subdirectory: The `All-In-Gentle` subdirectory name used by the
    ///     default directory resolution and error messages.
    ///   - fileManager: The file manager to use for disk operations.
    ///   - filenameStrategy: Maps a record id to a JSON filename.
    ///   - sortComparator: Orders records returned by `loadAll`.
    ///   - touch: Mutates a record in place immediately before it is encoded.
    public init(
        directory: URL? = nil,
        subdirectory: String,
        fileManager: FileManager = .default,
        filenameStrategy: @escaping @Sendable (String) -> String,
        sortComparator: @escaping @Sendable (Item, Item) -> Bool,
        touch: @escaping @Sendable (inout Item) -> Void
    ) {
        self.subdirectory = subdirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.filenameStrategy = filenameStrategy
        self.sortComparator = sortComparator
        self.touch = touch

        if let directory {
            self.directory = directory
        } else {
            self.directory = Self.resolveDefaultDirectory(
                urls: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask),
                fallback: fileManager.homeDirectoryForCurrentUser,
                subdirectory: subdirectory
            )
        }
    }

    /// Loads every record from the store directory, skipping corrupt files.
    public func loadAll() async throws -> [Item] {
        try ensureDirectoryExists()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        .filter { $0.pathExtension == "json" }

        var items: [Item] = []
        for url in urls {
            if let data = fileManager.contents(atPath: url.path),
               let item = try? decoder.decode(Item.self, from: data) {
                items.append(item)
            }
        }
        return items.sorted(by: sortComparator)
    }

    /// Saves a record to disk as atomic JSON, touching it first.
    @discardableResult
    public func save(_ item: Item) async throws -> Item {
        try ensureDirectoryExists()
        var item = item
        touch(&item)
        let url = fileURL(for: item.id)
        let data = try encoder.encode(item)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return item
    }

    /// Deletes a record from disk by id.
    public func delete(id: String) async throws {
        try fileManager.removeItem(at: fileURL(for: id))
    }

    /// Creates the store directory (idempotent) or throws if the path exists
    /// as a non-directory.
    public func ensureDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { return }
            throw AllInGentleError.persistenceFailure(
                "Store path for '\(subdirectory)' exists but is not a directory: \(directory.path)"
            )
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Resolves the default store directory from Application Support URLs,
    /// falling back to `~/Library/Application Support` when none is found.
    static func resolveDefaultDirectory(urls: [URL], fallback: URL, subdirectory: String) -> URL {
        let base = urls.first ?? fallback.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("All-In-Gentle/\(subdirectory)", isDirectory: true)
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent(filenameStrategy(id), isDirectory: false)
    }
}
