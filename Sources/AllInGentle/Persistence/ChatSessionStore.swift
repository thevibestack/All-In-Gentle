import Foundation

/// File-system persistence for ``ChatSession`` records.
///
/// ``ChatSessionStore`` reads and writes sessions as JSON in the app’s
/// Application Support directory under the `Sessions` subdirectory. All
/// public methods are async because the store is an actor and performs
/// file I/O.
public actor ChatSessionStore {
    private let fileManager: FileManager
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a store rooted at the given directory.
    ///
    /// - Parameters:
    ///   - directory: The directory in which session JSON files are stored.
    ///     Defaults to `~/Library/Application Support/All-In-Gentle/Sessions`.
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
            self.directory = appSupport.appendingPathComponent("All-In-Gentle/Sessions", isDirectory: true)
        }
    }

    /// Loads every session from the store directory.
    public func loadAll() async throws -> [ChatSession] {
        try ensureDirectoryExists()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        .filter { $0.pathExtension == "json" }

        var sessions: [ChatSession] = []
        for url in urls {
            if let data = fileManager.contents(atPath: url.path),
               let session = try? decoder.decode(ChatSession.self, from: data) {
                sessions.append(session)
            }
        }
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Saves a session to disk, creating a JSON file named after its id.
    ///
    /// If the session’s title is empty but it contains a user message, a
    /// generated title is assigned before saving.
    @discardableResult
    public func save(_ session: ChatSession) async throws -> ChatSession {
        try ensureDirectoryExists()
        var session = session
        if session.title.isEmpty {
            if let firstUserMessage = session.messages.first(where: { $0.role == .user }) {
                session.title = ChatSession.generatedTitle(from: firstUserMessage.content)
            }
        }
        session.updatedAt = Date()
        let url = fileURL(for: session.id)
        let data = try encoder.encode(session)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return session
    }

    /// Deletes a session from disk.
    public func delete(_ session: ChatSession) async throws {
        try fileManager.removeItem(at: fileURL(for: session.id))
    }

    /// Deletes a session by id.
    public func delete(id: String) async throws {
        try fileManager.removeItem(at: fileURL(for: id))
    }

    /// Duplicates a session, including its messages but with a new id and
    /// a derived title.
    @discardableResult
    public func duplicate(_ session: ChatSession) async throws -> ChatSession {
        let copy = ChatSession(
            title: duplicatedTitle(for: session),
            messages: session.messages.map {
                ChatMessage(
                    id: UUID().uuidString,
                    role: $0.role,
                    content: $0.content,
                    timestamp: $0.timestamp
                )
            },
            projectID: session.projectID,
            modelID: session.modelID
        )
        return try await save(copy)
    }

    /// Removes all messages from a session without deleting the session.
    @discardableResult
    public func clearMessages(_ session: ChatSession) async throws -> ChatSession {
        var cleared = session
        cleared.messages = []
        return try await save(cleared)
    }

    // MARK: - Helpers

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func ensureDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { return }
            throw AllInGentleError.persistenceFailure("Session store path exists but is not a directory: \(directory.path)")
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func duplicatedTitle(for session: ChatSession) -> String {
        let base = session.displayTitle
        let suffix = L("chat.session.duplicateSuffix")
        if base.isEmpty { return suffix }
        return "\(base) \(suffix)"
    }
}
