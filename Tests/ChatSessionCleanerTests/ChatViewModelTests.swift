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

    // MARK: - Retry & stream lifecycle (Wave 2 F6/F7)

    // R1: a failed send followed by retryLastSend() re-streams the persisted
    // user message exactly once — no duplication in memory or on disk.
    func testRetryReStreamsLastUserMessageWithoutDuplication() async throws {
        let service = ScriptedLLMService(script: [
            .failure(AllInGentleError.sourceUnavailable("network down")),
            .success([
                ChatChunk(textDelta: "Retried"),
                ChatChunk(textDelta: nil, finishReason: "stop")
            ])
        ])
        let viewModel = makeViewModel(service: service)
        viewModel.input = "Hi"

        await viewModel.send()
        XCTAssertNotNil(viewModel.errorMessage)

        await viewModel.retryLastSend()

        let userMessages = viewModel.messages.filter { $0.role == .user }
        XCTAssertEqual(userMessages.count, 1, "Retry must not duplicate the user message")
        XCTAssertEqual(userMessages.first?.content, "Hi")
        XCTAssertEqual(viewModel.messages.last?.role, .assistant)
        XCTAssertEqual(viewModel.messages.last?.content, "Retried")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isStreaming)

        let streamCalls = await service.streamCalls
        XCTAssertEqual(streamCalls, 2)
        let captured = await service.capturedCalls
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[1].filter { $0.role == .user }.count, 1,
                       "The retried stream must receive exactly one user message")

        let store = ChatSessionStore(directory: tempDirectory)
        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.first?.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(loaded.first?.messages.last?.content, "Retried")
    }

    // R2: when the store save failed, no persisted user message exists, so
    // retry is a documented no-op: state unchanged, banner untouched.
    func testRetryWithoutPersistedPayloadIsNoOp() async throws {
        let store = ChatSessionStore(directory: tempDirectory)
        let saved = try await store.save(ChatSession(title: "Empty", modelID: "deepseek"))
        let viewModel = makeViewModel(service: ScriptedLLMService(script: []))
        await viewModel.loadSessions()
        viewModel.selectSession(id: saved.id)

        // Break the store directory so persistence fails before any user
        // message can land in the in-memory session.
        try FileManager.default.removeItem(at: tempDirectory)
        try Data("not a directory".utf8).write(to: tempDirectory)

        viewModel.input = "Hi"
        await viewModel.send()
        XCTAssertNotNil(viewModel.errorMessage)

        let errorBeforeRetry = viewModel.errorMessage
        await viewModel.retryLastSend()

        XCTAssertEqual(viewModel.errorMessage, errorBeforeRetry,
                       "A payload-less retry must leave the error banner untouched")
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    // R3: retry without a provider surfaces the existing no-provider error and
    // never starts streaming.
    func testRetryWithoutProviderSurfacesNoProviderError() async throws {
        let store = ChatSessionStore(directory: tempDirectory)
        var session = ChatSession(title: "Provider check", modelID: "deepseek")
        session.messages.append(ChatMessage(id: "u1", role: .user, content: "Hello"))
        let saved = try await store.save(session)
        let service = ScriptedLLMService(script: [])
        let viewModel = makeViewModel(service: service)
        await viewModel.loadSessions()
        viewModel.selectSession(id: saved.id)

        preferences.llmProviderConfiguration = nil

        await viewModel.retryLastSend()

        XCTAssertEqual(viewModel.errorMessage, L("chat.error.noProvider"))
        XCTAssertFalse(viewModel.isStreaming)
        let streamCalls = await service.streamCalls
        XCTAssertEqual(streamCalls, 0, "No stream may start without a provider")
    }

    // Stream-error cleanup contract: the thrown error surfaces, streaming
    // stops, and no phantom (empty) assistant message survives.
    func testStreamErrorSurfacesErrorAndCleansUp() async throws {
        let error = AllInGentleError.sourceUnavailable("network down")
        let service = ScriptedLLMService(script: [.failure(error)])
        let viewModel = makeViewModel(service: service)
        viewModel.input = "Hello"

        await viewModel.send()

        XCTAssertEqual(viewModel.errorMessage, error.localizedDescription)
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertTrue(viewModel.messages.contains { $0.role == .user })
        XCTAssertFalse(viewModel.messages.contains { $0.role == .assistant },
                       "No empty assistant message may survive a stream error")
    }

    // R5: when the stream for session A finalizes after the user switched to
    // session B, the assistant message must land in A and B must stay untouched.
    func testMidStreamSessionSwitchFinalizesCorrectSession() async throws {
        let service = SuspendingLLMService()
        let viewModel = makeViewModel(service: service)
        let store = ChatSessionStore(directory: tempDirectory)
        let sessionA = try await store.save(ChatSession(title: "A", modelID: "deepseek"))
        let sessionB = try await store.save(ChatSession(title: "B", modelID: "deepseek"))
        await viewModel.loadSessions()
        viewModel.selectSession(id: sessionA.id)

        viewModel.input = "Hi"
        let sendTask = Task { await viewModel.send() }
        await service.waitForStreamingStart()

        viewModel.selectedSessionID = sessionB.id
        await service.release()
        await sendTask.value

        let finalA = viewModel.sessions.first { $0.id == sessionA.id }
        XCTAssertEqual(finalA?.messages.count, 2)
        XCTAssertEqual(finalA?.messages.last?.role, .assistant)
        XCTAssertEqual(finalA?.messages.last?.content, "Partial")
        let finalB = viewModel.sessions.first { $0.id == sessionB.id }
        XCTAssertTrue(finalB?.messages.isEmpty ?? false, "Session B must be untouched by A's stream")
        XCTAssertFalse(viewModel.isStreaming)
    }
}

// MARK: - Test doubles

/// LLM service double that plays a scripted queue of responses and records
/// every call it receives.
actor ScriptedLLMService: LLMService {
    private var script: [Result<[ChatChunk], Error>]
    private(set) var capturedCalls: [[ChatMessage]] = []
    private(set) var streamCalls = 0

    init(script: [Result<[ChatChunk], Error>]) {
        self.script = script
    }

    func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        capturedCalls.append(messages)
        streamCalls += 1
        guard !script.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }
        let response = script.removeFirst()
        return AsyncThrowingStream { continuation in
            switch response {
            case .success(let chunks):
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }
}

/// LLM service double that yields its first chunk, then suspends until
/// ``release()`` is called — used to hold a stream in flight mid-send.
actor SuspendingLLMService: LLMService {
    private let chunks: [ChatChunk]
    private var startSignal: CheckedContinuation<Void, Never>?
    private var releaseGate: CheckedContinuation<Void, Never>?
    private var started = false
    private var releasedEarly = false

    init(chunks: [ChatChunk] = [ChatChunk(textDelta: "Partial")]) {
        self.chunks = chunks
    }

    /// Suspends the caller until the first stream has started.
    func waitForStreamingStart() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                self.armStart(continuation)
            }
        }
    }

    /// Resumes any stream currently waiting on the release gate.
    func release() {
        if let releaseGate {
            releaseGate.resume()
            self.releaseGate = nil
        } else {
            releasedEarly = true
        }
    }

    func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { [chunks] continuation in
            Task {
                self.notifyStarted()
                continuation.yield(chunks[0])
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    Task {
                        self.armGate(continuation)
                    }
                }
                for chunk in chunks.dropFirst() {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    private func notifyStarted() {
        started = true
        if let startSignal {
            startSignal.resume()
            self.startSignal = nil
        }
    }

    private func armStart(_ continuation: CheckedContinuation<Void, Never>) {
        if started {
            continuation.resume()
        } else {
            startSignal = continuation
        }
    }

    private func armGate(_ continuation: CheckedContinuation<Void, Never>) {
        if releasedEarly {
            releasedEarly = false
            continuation.resume()
        } else {
            releaseGate = continuation
        }
    }
}
