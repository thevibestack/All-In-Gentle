import Foundation
import XCTest
@testable import AllInGentleKit

@MainActor
final class LLMServiceTests: XCTestCase {
    func testParseDeepSeekSSEStreamFromFixture() throws {
        guard let url = Bundle.module.url(forResource: "deepseek-stream", withExtension: "txt") else {
            XCTFail("Missing fixture deepseek-stream.txt")
            return
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        let chunks =
            try text
            .components(separatedBy: .newlines)
            .compactMap { line in
                try DeepSeekSSEParser.parse(line: line)
            }

        XCTAssertEqual(chunks.count, 3, "Fixture should yield three content/finish chunks before [DONE]")
        XCTAssertEqual(chunks[0].textDelta, "Hola")
        XCTAssertNil(chunks[0].finishReason)
        XCTAssertEqual(chunks[1].textDelta, " mundo")
        XCTAssertNil(chunks[1].finishReason)
        XCTAssertNil(chunks[2].textDelta)
        XCTAssertEqual(chunks[2].finishReason, "stop")
    }

    func testProviderSwitcherThrowsNoProviderWhenConfigMissing() async throws {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let switcher = ProviderSwitcher(preferences: store, keychain: MockKeychain())

        do {
            let stream = try await switcher.stream(messages: [])
            for try await _ in stream {}
            XCTFail("Expected stream to throw")
        } catch let error as AllInGentleError {
            guard case .invalidConfiguration(let message) = error else {
                XCTFail("Expected invalidConfiguration error, got \(error)")
                return
            }
            XCTAssertTrue(
                message == L("chat.error.noProvider"),
                "Unexpected message: \(message)"
            )
        } catch {
            XCTFail("Expected AllInGentleError.invalidConfiguration, got \(error)")
        }
    }

    func testProviderSwitcherReturnsStreamWhenConfigExists() async throws {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let config = LLMProviderConfiguration.deepseekDefault(id: "test")
        store.llmProviderConfiguration = config

        let keychain = MockKeychain()
        try await keychain.save(key: config.apiKeyAccount, value: "sk-test")

        MockURLProtocol.requestHandler = { request in
            let body = [
                "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}",
                "data: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":\"stop\"}]}",
                "data: [DONE]",
            ].joined(separator: "\n")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let switcher = ProviderSwitcher(
            preferences: store,
            keychain: keychain,
            urlSession: makeMockURLSession()
        )

        let stream = try await switcher.stream(messages: [])
        var chunks: [ChatChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
            if chunk.finishReason != nil { break }
        }

        XCTAssertEqual(chunks.map { $0.textDelta }, ["Hello", " world"])
        XCTAssertEqual(chunks.last?.finishReason, "stop")
    }

    func testDeepSeekProviderThrowsWhenKeyMissing() async throws {
        let config = LLMProviderConfiguration.deepseekDefault(id: "test")
        let provider = DeepSeekProvider(configuration: config, keychain: MockKeychain())

        do {
            let stream = try await provider.stream(messages: [])
            for try await _ in stream {}
            XCTFail("Expected stream to throw")
        } catch let error as AllInGentleError {
            guard case .invalidConfiguration = error else {
                XCTFail("Expected invalidConfiguration error, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected AllInGentleError, got \(error)")
        }
    }

    func testDeepSeekProviderPrependsSystemPrompt() async throws {
        let config = LLMProviderConfiguration.deepseekDefault(
            id: "test",
            systemPrompt: "You are a tester."
        )
        let keychain = MockKeychain()
        try await keychain.save(key: config.apiKeyAccount, value: "sk-test")

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let body = "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let provider = DeepSeekProvider(
            configuration: config,
            urlSession: makeMockURLSession(),
            keychain: keychain
        )
        let stream = try await provider.stream(messages: [
            ChatMessage(id: "1", role: .user, content: "Hi")
        ])
        for try await _ in stream {}

        guard let body = capturedRequest.flatMap(requestBody),
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            XCTFail("Expected JSON request body")
            return
        }

        guard let messages = json["messages"] as? [[String: String]] else {
            XCTFail("Expected messages array")
            return
        }

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "You are a tester.")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "Hi")
    }

    @MainActor
    func testChatViewModelSendsMessageWithConfiguredProvider() async throws {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let config = LLMProviderConfiguration.deepseekDefault(id: "chat-test")
        store.llmProviderConfiguration = config

        let keychain = MockKeychain()
        try await keychain.save(key: config.apiKeyAccount, value: "sk-test")

        MockURLProtocol.requestHandler = { request in
            let body = [
                "data: {\"choices\":[{\"delta\":{\"content\":\"Hola\"}}]}",
                "data: {\"choices\":[{\"delta\":{\"content\":\" mundo\"},\"finish_reason\":\"stop\"}]}",
            ].joined(separator: "\n")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let switcher = ProviderSwitcher(
            preferences: store,
            keychain: keychain,
            urlSession: makeMockURLSession()
        )
        let viewModel = ChatViewModel(service: switcher, preferences: store)
        viewModel.input = "Hi"

        await viewModel.send()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].content, "Hi")
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertEqual(viewModel.messages[1].content, "Hola mundo")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testChatViewModelSurfacesNoProviderError() async {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let switcher = ProviderSwitcher(preferences: store, keychain: MockKeychain())
        let viewModel = ChatViewModel(service: switcher)
        viewModel.input = "Hi"

        await viewModel.send()

        XCTAssertEqual(viewModel.messages.count, 0)
        XCTAssertEqual(viewModel.errorMessage, L("chat.error.noProvider"))
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testDeepSeekProviderSurfacesKeychainError() async throws {
        let config = LLMProviderConfiguration.deepseekDefault(id: "test")
        let keychain = MockKeychain()
        await keychain.setFailNextLoad()
        let provider = DeepSeekProvider(configuration: config, keychain: keychain)

        do {
            let stream = try await provider.stream(messages: [])
            for try await _ in stream {}
            XCTFail("Expected stream to throw")
        } catch let error as AllInGentleError {
            guard case .invalidConfiguration(let message) = error else {
                XCTFail("Expected invalidConfiguration error, got \(error)")
                return
            }
            XCTAssertTrue(
                message.contains("Keychain error"),
                "Expected keychain diagnostic, got: \(message)"
            )
        } catch {
            XCTFail("Expected AllInGentleError, got \(error)")
        }
    }

    // MARK: - Helpers

    private func makeEphemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "llm-service-tests-\(UUID().uuidString)")!
    }

    private func makeMockURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        let data = NSMutableData()
        var buffer = [UInt8](repeating: 0, count: 4096)
        stream.open()
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read > 0 {
                data.append(buffer, length: read)
            } else if read < 0 {
                break
            }
        }
        stream.close()
        return data as Data
    }
}

private actor MockKeychain: KeychainStoring {
    private var storage: [String: String] = [:]
    private var failNextSave = false
    private var failNextLoad = false

    func setFailNextSave() {
        failNextSave = true
    }

    func setFailNextLoad() {
        failNextLoad = true
    }

    func save(key: String, value: String) throws {
        if failNextSave {
            failNextSave = false
            throw AllInGentleError.persistenceFailure("Mock keychain save failure")
        }
        storage[key] = value
    }

    func load(key: String) throws -> String? {
        if failNextLoad {
            failNextLoad = false
            throw AllInGentleError.persistenceFailure("Mock keychain load failure")
        }
        return storage[key]
    }

    func delete(key: String) throws {
        storage[key] = nil
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
