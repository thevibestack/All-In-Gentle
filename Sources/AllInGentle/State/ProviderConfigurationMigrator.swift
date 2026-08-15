import Foundation

/// Migrates a legacy DeepSeek API key into a typed ``LLMProviderConfiguration``.
///
/// v1 stores a single provider in ``PreferencesStore`` and keeps the actual API
/// key in the Keychain. Users that installed earlier builds with the legacy
/// `all-in-gentle.deepseek-api-key` account are migrated automatically on the
/// first launch that detects a provider configuration is missing.
public actor ProviderConfigurationMigrator {
    /// Keychain account used by pre-provider builds to store the DeepSeek key.
    public static let legacyDeepSeekAccount = "all-in-gentle.deepseek-api-key"

    private let preferences: PreferencesStore
    private let keychain: any KeychainStoring

    public init(
        preferences: PreferencesStore,
        keychain: any KeychainStoring
    ) {
        self.preferences = preferences
        self.keychain = keychain
    }

    /// Migrates the legacy DeepSeek key into a provider configuration if needed.
    ///
    /// - Creates a DeepSeek ``LLMProviderConfiguration`` with sensible defaults.
    /// - Copies the legacy API key into the new provider Keychain account so
    ///   future settings edits and the provider adapter can share the same key.
    /// - Leaves the legacy key in place for safety.
    /// - Only persists the configuration AFTER the key copy succeeds; on
    ///   failure the config stays nil and the guard retries next launch.
    public func migrateIfNeeded() async {
        guard preferences.llmProviderConfiguration == nil else { return }

        guard let apiKey = try? await keychain.load(key: Self.legacyDeepSeekAccount), !apiKey.isEmpty else {
            return
        }

        let config = LLMProviderConfiguration.deepseekDefault(
            id: "deepseek",
            apiKeyReference: LLMProviderConfiguration.keychainAccount(for: "deepseek")
        )

        do {
            try await keychain.save(key: config.apiKeyAccount, value: apiKey)
        } catch {
            // Config stays nil and the legacy key stays in place; the guard
            // re-runs on the next launch.
            return
        }

        preferences.llmProviderConfiguration = config
    }
}
