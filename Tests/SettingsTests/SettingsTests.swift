import Foundation
import XCTest
@testable import AllInGentleKit

@MainActor
final class SettingsTests: XCTestCase {
    func testMigrationCreatesProviderFromLegacyKeychain() async throws {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let keychain = MockKeychain()
        try await keychain.save(key: ProviderConfigurationMigrator.legacyDeepSeekAccount, value: "sk-legacy")

        let migrator = ProviderConfigurationMigrator(
            preferences: store,
            keychain: keychain
        )
        await migrator.migrateIfNeeded()

        let config = store.llmProviderConfiguration
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.providerType, .deepseek)
        XCTAssertEqual(config?.displayName, "DeepSeek")
        XCTAssertEqual(config?.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(config?.model, "deepseek-chat")
        XCTAssertEqual(config?.apiKeyReference, "all-in-gentle.provider.deepseek.api-key")

        let migratedKey = await keychain.load(key: "all-in-gentle.provider.deepseek.api-key")
        XCTAssertEqual(migratedKey, "sk-legacy")

        let legacyKeyStillPresent = await keychain.load(key: ProviderConfigurationMigrator.legacyDeepSeekAccount)
        XCTAssertEqual(legacyKeyStillPresent, "sk-legacy")
    }

    func testMigrationSkippedWhenConfigAlreadyExists() async throws {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let existing = LLMProviderConfiguration(
            id: "custom",
            providerType: .deepseek,
            displayName: "Custom",
            baseURL: "https://custom.example.com",
            model: "custom-model",
            temperature: 0.5,
            apiKeyReference: "all-in-gentle.provider.custom.api-key"
        )
        store.llmProviderConfiguration = existing

        let keychain = MockKeychain()
        try await keychain.save(key: ProviderConfigurationMigrator.legacyDeepSeekAccount, value: "sk-legacy")

        let migrator = ProviderConfigurationMigrator(
            preferences: store,
            keychain: keychain
        )
        await migrator.migrateIfNeeded()

        XCTAssertEqual(store.llmProviderConfiguration?.displayName, "Custom")

        let migratedKey = await keychain.load(key: "all-in-gentle.provider.deepseek.api-key")
        XCTAssertNil(migratedKey)
    }

    func testMigrationSkippedWhenLegacyKeyMissing() async {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let keychain = MockKeychain()

        let migrator = ProviderConfigurationMigrator(
            preferences: store,
            keychain: keychain
        )
        await migrator.migrateIfNeeded()

        XCTAssertNil(store.llmProviderConfiguration)
    }

    func testAISettingsViewCanBeConstructed() {
        let view = AISettingsView()
        XCTAssertNotNil(view)
    }

    func testAppStateInitializesMigration() {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let keychain = MockKeychain()

        let migrator = ProviderConfigurationMigrator(
            preferences: store,
            keychain: keychain
        )

        let appState = AppState(preferences: store, migrator: migrator)
        XCTAssertEqual(appState.selectedItem, .projects)
    }

    // MARK: - Connection test (F9)

    func testConnectionSuccessUsesDraftConfigAndRestoresKeychain() async throws {
        let config = LLMProviderConfiguration.deepseekDefault(id: "conn-test")
        let keychain = MockKeychain()
        try await keychain.save(key: config.apiKeyAccount, value: "sk-old")

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let body = [
                "data: {\"choices\":[{\"delta\":{\"content\":\"pong\"},\"finish_reason\":\"stop\"}]}",
                "data: [DONE]"
            ].joined(separator: "\n")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let result = await AISettingsView.performConnectionTest(
            configuration: config,
            apiKey: "sk-draft",
            keychain: keychain,
            urlSession: makeMockURLSession()
        )

        XCTAssertEqual(result, .success(L("settings.ai.test.success")))

        // Draft key was persisted for the call, previous key restored afterwards.
        guard let request = capturedRequest else {
            XCTFail("Expected the request to be captured")
            return
        }
        XCTAssertEqual(request.url?.absoluteString.hasSuffix("chat/completions"), true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-draft")

        guard let body = requestBody(from: request),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            XCTFail("Expected a JSON request body")
            return
        }
        XCTAssertEqual(json["model"] as? String, config.model)
        XCTAssertEqual((json["max_tokens"] as? NSNumber)?.intValue, 1)

        guard let messages = json["messages"] as? [[String: String]], messages.count == 1 else {
            XCTFail("Expected exactly one message, got \(json["messages"] ?? "nil")")
            return
        }
        XCTAssertEqual(messages[0], ["role": "user", "content": "ping"])

        let restoredKey = await keychain.load(key: config.apiKeyAccount)
        XCTAssertEqual(restoredKey, "sk-old")
    }

    func testConnectionFailureShowsLocalizedErrorAndRestoresKeychain() async throws {
        let config = LLMProviderConfiguration.deepseekDefault(id: "conn-test")
        let keychain = MockKeychain()
        try await keychain.save(key: config.apiKeyAccount, value: "sk-old")

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{\"error\":\"unauthorized\"}".utf8))
        }

        let result = await AISettingsView.performConnectionTest(
            configuration: config,
            apiKey: "sk-draft",
            keychain: keychain,
            urlSession: makeMockURLSession()
        )

        XCTAssertEqual(result, .failure(L("settings.ai.test.failure")))
        let restoredKey = await keychain.load(key: config.apiKeyAccount)
        XCTAssertEqual(restoredKey, "sk-old")
    }

    func testConnectionWithoutPreviousKeyDeletesDraftKey() async throws {
        let config = LLMProviderConfiguration.deepseekDefault(id: "conn-test")
        let keychain = MockKeychain()

        MockURLProtocol.requestHandler = { request in
            let body = "data: {\"choices\":[{\"delta\":{\"content\":\"pong\"},\"finish_reason\":\"stop\"}]}\n"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let result = await AISettingsView.performConnectionTest(
            configuration: config,
            apiKey: "sk-draft",
            keychain: keychain,
            urlSession: makeMockURLSession()
        )

        XCTAssertEqual(result, .success(L("settings.ai.test.success")))
        let remainingKey = await keychain.load(key: config.apiKeyAccount)
        XCTAssertNil(remainingKey)
    }

    // MARK: - Helpers

    private func makeEphemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "settings-tests-\(UUID().uuidString)")!
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

private actor MockKeychain: KeychainStoring {
    private var storage: [String: String] = [:]

    func save(key: String, value: String) throws {
        storage[key] = value
    }

    func load(key: String) -> String? {
        storage[key]
    }

    func delete(key: String) {
        storage[key] = nil
    }
}
