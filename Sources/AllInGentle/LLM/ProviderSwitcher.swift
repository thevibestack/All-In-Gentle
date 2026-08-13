import Foundation

/// Placeholder router that currently delegates every request to DeepSeek.
///
/// ``ProviderSwitcher`` implements ``LLMService`` so the rest of the app can
/// depend on a single service abstraction. When a second provider is added,
/// routing logic can be introduced here without changing call sites.
public actor ProviderSwitcher: LLMService {
    private let active: LLMService

    public init(provider: LLMService = DeepSeekProvider()) {
        self.active = provider
    }

    public func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        try await active.stream(messages: messages)
    }
}
