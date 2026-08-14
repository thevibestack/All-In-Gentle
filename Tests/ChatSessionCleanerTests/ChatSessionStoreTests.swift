import XCTest
@testable import AllInGentleKit

@MainActor
final class ChatSessionStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-session-store-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    private func makeStore() -> ChatSessionStore {
        ChatSessionStore(directory: tempDirectory)
    }

    func testLoadAllReturnsEmptyWhenDirectoryDoesNotExist() async throws {
        let store = makeStore()
        let sessions = try await store.loadAll()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testSaveAndLoadSession() async throws {
        let store = makeStore()
        let session = ChatSession(title: "Test", modelID: "deepseek")
        let saved = try await store.save(session)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, saved.id)
        XCTAssertEqual(loaded.first?.title, "Test")
        XCTAssertEqual(loaded.first?.modelID, "deepseek")
    }

    func testSaveGeneratesTitleFromFirstUserMessage() async throws {
        let store = makeStore()
        var session = ChatSession(title: "", modelID: "deepseek")
        session.messages.append(ChatMessage(id: "1", role: .user, content: "Explain this code to me please"))
        let saved = try await store.save(session)

        XCTAssertEqual(saved.title, "Explain this code to me please")
    }

    func testDeleteSession() async throws {
        let store = makeStore()
        let session = ChatSession(title: "To delete", modelID: "deepseek")
        let saved = try await store.save(session)
        try await store.delete(saved)

        let loaded = try await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDuplicateSession() async throws {
        let store = makeStore()
        var session = ChatSession(title: "Original", modelID: "deepseek")
        session.messages.append(ChatMessage(id: "1", role: .user, content: "Hi"))
        let saved = try await store.save(session)
        let copy = try await store.duplicate(saved)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(copy.title.hasPrefix("Original"))
        XCTAssertNotEqual(copy.title, "Original")
        XCTAssertEqual(copy.messages.count, 1)
        XCTAssertNotEqual(copy.id, saved.id)
    }

    func testClearMessagesKeepsSession() async throws {
        let store = makeStore()
        var session = ChatSession(title: "Clear me", modelID: "deepseek")
        session.messages.append(ChatMessage(id: "1", role: .user, content: "Hi"))
        let saved = try await store.save(session)
        let cleared = try await store.clearMessages(saved)

        XCTAssertTrue(cleared.messages.isEmpty)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.first?.messages.count, 0)
        XCTAssertEqual(loaded.first?.title, "Clear me")
    }
}
