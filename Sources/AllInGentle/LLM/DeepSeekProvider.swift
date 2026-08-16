import Foundation

/// DeepSeek adapter implementing ``LLMService`` via OpenAI-compatible SSE streaming.
public actor DeepSeekProvider: LLMService {
    private let configuration: LLMProviderConfiguration
    private let urlSession: URLSession
    private let keychain: any KeychainStoring

    public init(
        configuration: LLMProviderConfiguration,
        urlSession: URLSession = URLSession(configuration: .makeAppDefault()),
        keychain: any KeychainStoring
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.keychain = keychain
    }

    public func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        let apiKey: String
        do {
            apiKey = try await keychain.load(key: configuration.apiKeyAccount) ?? ""
        } catch {
            throw AllInGentleError.invalidConfiguration(
                "Keychain error reading API key for provider '\(configuration.displayName)': \(error.localizedDescription)"
            )
        }
        guard !apiKey.isEmpty else {
            throw AllInGentleError.invalidConfiguration(
                "API key not found in keychain for provider '\(configuration.displayName)'"
            )
        }

        guard let baseURL = URL(string: configuration.baseURL) else {
            throw AllInGentleError.invalidConfiguration(
                "Invalid base URL for provider '\(configuration.displayName)': \(configuration.baseURL)"
            )
        }

        var requestMessages = messages
        if let systemPrompt = configuration.systemPrompt, !systemPrompt.isEmpty {
            requestMessages.insert(
                ChatMessage(id: UUID().uuidString, role: .system, content: systemPrompt),
                at: 0
            )
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        let request: URLRequest = {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let body = RequestBody(
                model: configuration.model,
                messages: requestMessages.map { RequestBody.Message(role: $0.role.rawValue, content: $0.content) },
                stream: true,
                temperature: configuration.temperature,
                maxTokens: configuration.maxTokens
            )
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try? encoder.encode(body)
            return request
        }()

        let session = self.urlSession

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(
                            throwing: AllInGentleError.sourceUnavailable("DeepSeek returned a non-HTTP response"))
                        return
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var bodyText = ""
                        for try await line in bytes.lines {
                            bodyText.append(line)
                            bodyText.append("\n")
                        }
                        continuation.finish(
                            throwing: AllInGentleError.sourceUnavailable(
                                "DeepSeek returned HTTP \(http.statusCode): \(bodyText.prefix(200))"
                            )
                        )
                        return
                    }

                    for try await line in bytes.lines {
                        if let chunk = try DeepSeekSSEParser.parse(line: line) {
                            continuation.yield(chunk)
                            if chunk.finishReason != nil {
                                break
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Request / response models

private struct RequestBody: Encodable, Sendable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double?
    let maxTokens: Int?

    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }
}

private struct StreamChunk: Decodable, Sendable {
    let choices: [Choice]

    struct Choice: Decodable, Sendable {
        let delta: Delta?
        let finishReason: String?
    }

    struct Delta: Decodable, Sendable {
        let content: String?
    }
}

// MARK: - SSE parsing

enum DeepSeekSSEParser {
    /// Parses a single SSE line into a ``ChatChunk``.
    ///
    /// Returns `nil` for empty lines, comments, or the `[DONE]` terminator.
    static func parse(line: String) throws -> ChatChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(":") {
            return nil
        }
        guard trimmed.hasPrefix("data: ") else {
            return nil
        }

        let payload = String(trimmed.dropFirst("data: ".count))
        guard payload != "[DONE]" else {
            return nil
        }
        guard let data = payload.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let chunk = try decoder.decode(StreamChunk.self, from: data)
        guard let choice = chunk.choices.first else {
            return nil
        }

        return ChatChunk(
            textDelta: choice.delta?.content,
            finishReason: choice.finishReason
        )
    }
}
