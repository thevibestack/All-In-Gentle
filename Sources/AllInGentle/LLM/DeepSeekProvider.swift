import Foundation

/// DeepSeek adapter implementing ``LLMService`` via OpenAI-compatible SSE streaming.
public actor DeepSeekProvider: LLMService {
    /// Keychain account string used to store the DeepSeek API key.
    public static let apiKeyKey = "all-in-gentle.deepseek-api-key"

    private let baseURL: URL
    private let urlSession: URLSession
    private let keychain: KeychainStore

    public init(
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        urlSession: URLSession = .shared,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.keychain = keychain
    }

    public func stream(messages: [ChatMessage]) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        guard let apiKey = await keychain.load(key: Self.apiKeyKey), !apiKey.isEmpty else {
            throw AllInGentleError.invalidConfiguration("DeepSeek API key not found in keychain")
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        let request: URLRequest = {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let body = RequestBody(
                model: "deepseek-chat",
                messages: messages.map { RequestBody.Message(role: $0.role.rawValue, content: $0.content) },
                stream: true
            )
            request.httpBody = try? JSONEncoder().encode(body)
            return request
        }()

        let session = self.urlSession

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AllInGentleError.sourceUnavailable("DeepSeek returned a non-HTTP response"))
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
