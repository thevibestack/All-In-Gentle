import Foundation
import XCTest
@testable import AllInGentleKit
import AllInGentleTestSupport

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

        let migratedKey = try? await keychain.load(key: "all-in-gentle.provider.deepseek.api-key")
        XCTAssertEqual(migratedKey, "sk-legacy")

        let legacyKeyStillPresent = try? await keychain.load(key: ProviderConfigurationMigrator.legacyDeepSeekAccount)
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

        let migratedKey = try? await keychain.load(key: "all-in-gentle.provider.deepseek.api-key")
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
        MockURLProtocol.box.set { request in
            capturedRequest = request
            let body = [
                "data: {\"choices\":[{\"delta\":{\"content\":\"pong\"},\"finish_reason\":\"stop\"}]}",
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
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
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

        let restoredKey = try? await keychain.load(key: config.apiKeyAccount)
        XCTAssertEqual(restoredKey, "sk-old")
    }

    func testConnectionFailureShowsLocalizedErrorAndRestoresKeychain() async throws {
        let config = LLMProviderConfiguration.deepseekDefault(id: "conn-test")
        let keychain = MockKeychain()
        try await keychain.save(key: config.apiKeyAccount, value: "sk-old")

        MockURLProtocol.box.set { request in
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
        let restoredKey = try? await keychain.load(key: config.apiKeyAccount)
        XCTAssertEqual(restoredKey, "sk-old")
    }

    func testConnectionWithoutPreviousKeyDeletesDraftKey() async throws {
        let config = LLMProviderConfiguration.deepseekDefault(id: "conn-test")
        let keychain = MockKeychain()

        MockURLProtocol.box.set { request in
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
        let remainingKey = try? await keychain.load(key: config.apiKeyAccount)
        XCTAssertNil(remainingKey)
    }

    func testMigrationNoDanglingConfigWhenKeySaveFails() async throws {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let keychain = MockKeychain()
        try await keychain.save(key: ProviderConfigurationMigrator.legacyDeepSeekAccount, value: "sk-legacy")
        await keychain.setFailNextSave()

        let migrator = ProviderConfigurationMigrator(
            preferences: store,
            keychain: keychain
        )
        await migrator.migrateIfNeeded()

        XCTAssertNil(store.llmProviderConfiguration, "Config must stay nil when the key copy fails")

        let legacyKeyStillPresent = try await keychain.load(key: ProviderConfigurationMigrator.legacyDeepSeekAccount)
        XCTAssertEqual(legacyKeyStillPresent, "sk-legacy")
        let migratedKey = try await keychain.load(key: "all-in-gentle.provider.deepseek.api-key")
        XCTAssertNil(migratedKey)
    }

    func testMigrationSkipsWhenKeychainLoadThrows() async {
        let defaults = makeEphemeralDefaults()
        let store = PreferencesStore(defaults: defaults)
        let keychain = MockKeychain()
        await keychain.setFailNextLoad()

        let migrator = ProviderConfigurationMigrator(
            preferences: store,
            keychain: keychain
        )
        await migrator.migrateIfNeeded()

        XCTAssertNil(store.llmProviderConfiguration)
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
