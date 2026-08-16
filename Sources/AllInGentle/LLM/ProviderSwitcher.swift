import Foundation

/// Router that creates the configured ``LLMService`` on demand.
///
/// ``ProviderSwitcher`` reads the persisted ``LLMProviderConfiguration`` from
/// ``PreferencesStore`` and instantiates the concrete provider with its Keychain
/// API key. v1 supports a single DeepSeek provider; the structure is designed so
/// adding future providers only changes this file.
public actor ProviderSwitcher: LLMService {
    private let preferences: PreferencesStore
    private let keychain: any KeychainStoring
    private let urlSession: URLSession

    public init(
        preferences: PreferencesStore = PreferencesStore(),
        keychain: any KeychainStoring = KeychainStore(),
        urlSession: URLSession = URLSession(configuration: .makeAppDefault())
    ) {
        self.preferences = preferences
        self.keychain = keychain
        self.urlSession = urlSession
    }

    public func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        guard let configuration = preferences.llmProviderConfiguration else {
            return AsyncThrowingStream { continuation in
                continuation.finish(
                    throwing: AllInGentleError.invalidConfiguration(L("chat.error.noProvider"))
                )
            }
        }

        let service = DeepSeekProvider(
            configuration: configuration,
            urlSession: urlSession,
            keychain: keychain
        )
        return try await service.stream(messages: messages)
    }
}
