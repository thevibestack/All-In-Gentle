import XCTest
@testable import AllInGentleKit

@MainActor
final class ChatViewModelTests: XCTestCase {
    private var tempDirectory: URL!
    private var preferences: PreferencesStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-view-model-tests-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "chat-view-model-tests-\(UUID().uuidString)")!
        preferences = PreferencesStore(defaults: defaults)
        preferences.llmProviderConfiguration = LLMProviderConfiguration.deepseekDefault(id: "deepseek")
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    private func makeViewModel(service: LLMService = MockLLMService(chunks: [])) -> ChatViewModel {
        ChatViewModel(
            service: service,
            store: ChatSessionStore(directory: tempDirectory),
            preferences: preferences
        )
    }

    func testNewSessionCreatesAndSelectsSession() async {
        let viewModel = makeViewModel()
        viewModel.newSession()

        // Wait for the async save to complete.
        let deadline = Date().addingTimeInterval(2)
        while viewModel.sessions.isEmpty && Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.selectedSessionID, viewModel.sessions.first?.id)
    }

    func testRenameSessionUpdatesTitle() async {
        let viewModel = makeViewModel()
        let session = ChatSession(title: "Old", modelID: "deepseek")
        let store = ChatSessionStore(directory: tempDirectory)
        let saved = try! await store.save(session)
        await viewModel.loadSessions()

        viewModel.renameSession(saved, newTitle: "New title")

        let deadline = Date().addingTimeInterval(2)
        while viewModel.sessions.first?.title != "New title" && Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.sessions.first?.title, "New title")
    }

    func testDeleteSessionRemovesAndDeselects() async {
        let viewModel = makeViewModel()
        let session = ChatSession(title: "To delete", modelID: "deepseek")
        let store = ChatSessionStore(directory: tempDirectory)
        let saved = try! await store.save(session)
        await viewModel.loadSessions()

        viewModel.deleteSession(saved)

        let deadline = Date().addingTimeInterval(2)
        while !viewModel.sessions.isEmpty && Date() < deadline {
            await Task.yield()
        }

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNil(viewModel.selectedSessionID)
    }

    func testSendMessagePersistsToStore() async throws {
        let service = MockLLMService(chunks: [
            ChatChunk(textDelta: "Hello"),
            ChatChunk(textDelta: " world"),
            ChatChunk(textDelta: nil, finishReason: "stop")
        ])
        let viewModel = makeViewModel(service: service)
        viewModel.input = "Hi"

        await viewModel.send()

        let store = ChatSessionStore(directory: tempDirectory)
        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.messages.count, 2)
        XCTAssertEqual(loaded.first?.messages[0].role, .user)
        XCTAssertEqual(loaded.first?.messages[0].content, "Hi")
        XCTAssertEqual(loaded.first?.messages[1].role, .assistant)
        XCTAssertEqual(loaded.first?.messages[1].content, "Hello world")
        XCTAssertEqual(loaded.first?.title, "Hi")
    }

    func testFilterSessionsByTitleOrUserMessage() async {
        let viewModel = makeViewModel()
        let store = ChatSessionStore(directory: tempDirectory)
        var alpha = ChatSession(title: "Alpha session", modelID: "deepseek")
        alpha.messages.append(ChatMessage(id: "1", role: .user, content: "Hello there"))
        let beta = ChatSession(title: "Beta", modelID: "deepseek")
        try! await store.save(alpha)
        try! await store.save(beta)
        await viewModel.loadSessions()

        viewModel.searchQuery = "alpha"
        XCTAssertEqual(viewModel.filteredSessions.count, 1)
        XCTAssertEqual(viewModel.filteredSessions.first?.title, "Alpha session")

        viewModel.searchQuery = "hello"
        XCTAssertEqual(viewModel.filteredSessions.count, 1)
        XCTAssertEqual(viewModel.filteredSessions.first?.title, "Alpha session")

        viewModel.searchQuery = "beta"
        XCTAssertEqual(viewModel.filteredSessions.count, 1)

        viewModel.searchQuery = ""
        XCTAssertEqual(viewModel.filteredSessions.count, 2)
    }

    func testFilterMessagesBySearchQuery() async {
        let viewModel = makeViewModel()
        let store = ChatSessionStore(directory: tempDirectory)
        var session = ChatSession(title: "Filter test", modelID: "deepseek")
        session.messages.append(ChatMessage(id: "1", role: .user, content: "Hello world"))
        session.messages.append(ChatMessage(id: "2", role: .assistant, content: "Goodbye moon"))
        let saved = try! await store.save(session)
        await viewModel.loadSessions()
        viewModel.selectSession(id: saved.id)

        viewModel.messageSearchQuery = "hello"
        XCTAssertEqual(viewModel.filteredMessages.count, 1)
        XCTAssertEqual(viewModel.filteredMessages.first?.role, .user)

        viewModel.messageSearchQuery = "moon"
        XCTAssertEqual(viewModel.filteredMessages.count, 1)
        XCTAssertEqual(viewModel.filteredMessages.first?.role, .assistant)

        viewModel.messageSearchQuery = ""
        XCTAssertEqual(viewModel.filteredMessages.count, 2)
    }
}
