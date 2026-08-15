import Foundation

/// File-system persistence for ``ChatSession`` records.
///
/// ``ChatSessionStore`` reads and writes sessions as JSON in the app’s
/// Application Support directory under the `Sessions` subdirectory. All
/// public methods are async because the store is an actor and performs
/// file I/O. The store is a thin facade over ``FileBackedJSONStore``.
public actor ChatSessionStore {
    private let store: FileBackedJSONStore<ChatSession>

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
        let resolvedDirectory = directory ?? Self.resolveDefaultDirectory(
            fileManager: fileManager,
            subdirectory: "Sessions"
        )
        self.store = FileBackedJSONStore(
            directory: resolvedDirectory,
            subdirectory: "Sessions",
            filenameStrategy: { "\($0).json" },
            sortComparator: { $0.updatedAt > $1.updatedAt },
            touch: { $0.updatedAt = Date() }
        )
    }

    private static func resolveDefaultDirectory(fileManager: FileManager, subdirectory: String) -> URL {
        FileBackedJSONStore<ChatSession>.resolveDefaultDirectory(
            urls: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask),
            fallback: fileManager.homeDirectoryForCurrentUser,
            subdirectory: subdirectory
        )
    }

    /// Loads every session from the store directory, newest first.
    public func loadAll() async throws -> [ChatSession] {
        try await store.loadAll()
    }

    /// Saves a session to disk, creating a JSON file named after its id.
    ///
    /// If the session’s title is empty but it contains a user message, a
    /// generated title is assigned before saving.
    @discardableResult
    public func save(_ session: ChatSession) async throws -> ChatSession {
        var session = session
        if session.title.isEmpty {
            if let firstUserMessage = session.messages.first(where: { $0.role == .user }) {
                session.title = ChatSession.generatedTitle(from: firstUserMessage.content)
            }
        }
        return try await store.save(session)
    }

    /// Deletes a session from disk.
    public func delete(_ session: ChatSession) async throws {
        try await store.delete(id: session.id)
    }

    /// Deletes a session by id.
    public func delete(id: String) async throws {
        try await store.delete(id: id)
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

    private func duplicatedTitle(for session: ChatSession) -> String {
        let base = session.displayTitle
        let suffix = L("chat.session.duplicateSuffix")
        if base.isEmpty { return suffix }
        return "\(base) \(suffix)"
    }
}
