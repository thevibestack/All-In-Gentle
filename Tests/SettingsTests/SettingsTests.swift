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

    // MARK: - Helpers

    private func makeEphemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "settings-tests-\(UUID().uuidString)")!
    }
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
