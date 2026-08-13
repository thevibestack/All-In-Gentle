import Foundation

/// A single chunk emitted by an LLM streaming response.
public struct ChatChunk: Sendable {
    /// Text delta for this chunk, if any.
    public let textDelta: String?
    /// Completion signal, if the provider finished generation.
    public let finishReason: String?

    public init(textDelta: String? = nil, finishReason: String? = nil) {
        self.textDelta = textDelta
        self.finishReason = finishReason
    }
}

/// Provider-agnostic chat service.
///
/// Callers send a history of messages and receive an asynchronous stream of
/// ``ChatChunk`` values. Concrete providers may route to DeepSeek, OpenAI, or
/// any other OpenAI-compatible endpoint.
public protocol LLMService: Sendable {
    /// Stream chat completions for the provided message history.
    func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error>
}
