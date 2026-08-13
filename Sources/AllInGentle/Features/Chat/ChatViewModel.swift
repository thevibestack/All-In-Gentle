import Foundation
import Observation

/// View model for the research chat tab.
///
/// Sends the current message history to ``LLMService`` and appends the
/// streaming assistant response. The provider switch remains a placeholder
/// outside this view model; the active service is injected on creation.
@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var messages: [ChatMessage] = []
    public var input: String = ""
    public private(set) var isStreaming: Bool = false
    public var errorMessage: String?
    public var searchQuery: String = ""

    public var filteredMessages: [ChatMessage] {
        if searchQuery.isEmpty { return messages }
        return messages.filter { $0.content.localizedCaseInsensitiveContains(searchQuery) }
    }

    private let service: LLMService

    public init(service: LLMService = ProviderSwitcher()) {
        self.service = service
    }

    /// Sends the user's current input and streams the assistant reply.
    public func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text
        )
        messages.append(userMessage)
        input = ""
        isStreaming = true
        errorMessage = nil
        defer { isStreaming = false }

        do {
            let stream = try await service.stream(messages: messages)
            var responseText = ""
            for try await chunk in stream {
                if let delta = chunk.textDelta {
                    responseText += delta
                }
                if chunk.finishReason != nil {
                    break
                }
            }
            messages.append(
                ChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: responseText
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
