import XCTest
@testable import AllInGentleKit

@MainActor
final class ChatSessionCleanerTests: XCTestCase {

    // MARK: - Chat

    // MARK: - Chat

    func testChatViewModelAppendsUserAndAssistantMessages() async {
        let service = MockLLMService(chunks: [
            ChatChunk(textDelta: "Hola"),
            ChatChunk(textDelta: " mundo"),
            ChatChunk(textDelta: nil, finishReason: "stop"),
        ])
        let viewModel = ChatViewModel(
            service: service,
            preferences: configuredPreferences()
        )
        viewModel.input = "Hi"

        await viewModel.send()

        // send() returns once the generation task is created; wait for the
        // stream to complete before asserting its effects.
        let deadline = Date().addingTimeInterval(2)
        while viewModel.isStreaming && Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].content, "Hi")
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertEqual(viewModel.messages[1].content, "Hola mundo")
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testChatViewModelSurfacesStreamError() async {
        let service = FailingLLMService()
        let viewModel = ChatViewModel(
            service: service,
            preferences: configuredPreferences()
        )
        viewModel.input = "Hello"

        await viewModel.send()

        let deadline = Date().addingTimeInterval(2)
        while viewModel.isStreaming && Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testChatViewModelIgnoresEmptyInput() async {
        let service = MockLLMService(chunks: [])
        let viewModel = ChatViewModel(
            service: service,
            preferences: configuredPreferences()
        )
        viewModel.input = "   "

        await viewModel.send()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isStreaming)
    }

    // MARK: - Session Cleaner

    func testSessionCleanerGroupsSessionsByProject() {
        let sessions = [
            SessionSummary(
                id: "s1",
                project: "proj-a",
                sessionName: "A1",
                messageCount: 0,
                totalTokens: 100,
                estimatedCost: 0.001,
                latestDate: Date(timeIntervalSince1970: 1000)
            ),
            SessionSummary(
                id: "s2",
                project: "proj-a",
                sessionName: "A2",
                messageCount: 0,
                totalTokens: 50,
                estimatedCost: 0.0005,
                latestDate: Date(timeIntervalSince1970: 2000)
            ),
            SessionSummary(
                id: "s3",
                project: "proj-b",
                sessionName: "B1",
                messageCount: 0,
                totalTokens: 30,
                estimatedCost: 0.0003,
                latestDate: Date(timeIntervalSince1970: 1500)
            ),
        ]
        let projects = [
            Project(id: "proj-a", name: "Project Alpha", path: "/alpha", source: .opencode),
            Project(id: "proj-b", name: "", path: "/beta", source: .opencode),
        ]

        let viewModel = SessionCleanerViewModel(sessions: sessions, projects: projects)

        XCTAssertEqual(viewModel.groups.count, 2)

        let groupA = viewModel.groups.first { $0.id == "proj-a" }
        XCTAssertEqual(groupA?.name, "Project Alpha")
        XCTAssertEqual(groupA?.sessions.count, 2)
        XCTAssertEqual(groupA?.totalTokens, 150)
        XCTAssertEqual(groupA?.totalCost ?? 0, 0.0015, accuracy: 1e-10)
        XCTAssertEqual(groupA?.latestDate, Date(timeIntervalSince1970: 2000))

        let groupB = viewModel.groups.first { $0.id == "proj-b" }
        XCTAssertEqual(groupB?.name, "proj-b")
        XCTAssertEqual(groupB?.sessions.count, 1)
        XCTAssertEqual(groupB?.totalTokens, 30)
    }

    func testSessionCleanerSortsGroupsByName() {
        let sessions = [
            SessionSummary(
                id: "s1",
                project: "zebra",
                sessionName: "Z1",
                messageCount: 0,
                totalTokens: 1,
                estimatedCost: 0,
                latestDate: Date()
            ),
            SessionSummary(
                id: "s2",
                project: "alpha",
                sessionName: "A1",
                messageCount: 0,
                totalTokens: 1,
                estimatedCost: 0,
                latestDate: Date()
            ),
        ]

        let viewModel = SessionCleanerViewModel(sessions: sessions, projects: [])

        XCTAssertEqual(viewModel.groups.map(\.id), ["alpha", "zebra"])
    }

    private func configuredPreferences() -> PreferencesStore {
        let defaults = UserDefaults(suiteName: "chat-session-cleaner-tests-\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)
        store.llmProviderConfiguration = LLMProviderConfiguration.deepseekDefault(id: "test")
        return store
    }
}

// MARK: - Test doubles

struct MockLLMService: LLMService {
    let chunks: [ChatChunk]

    func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

struct FailingLLMService: LLMService {
    func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        throw AllInGentleError.sourceUnavailable("network down")
    }
}

/// Test double whose stream yields optional prefix chunks and never finishes.
///
/// F17: the stream stays open so tests can observe cancellation through
/// `onTermination` and verify that a view model is not retained by its
/// streaming task while a generation is in flight.
struct HangingLLMService: LLMService {
    let chunks: [ChatChunk]
    let onTerminated: (@Sendable () -> Void)?

    init(
        chunks: [ChatChunk] = [ChatChunk(textDelta: "partial")],
        onTerminated: (@Sendable () -> Void)? = nil
    ) {
        self.chunks = chunks
        self.onTerminated = onTerminated
    }

    func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.onTermination = { _ in
                onTerminated?()
            }
        }
    }
}
