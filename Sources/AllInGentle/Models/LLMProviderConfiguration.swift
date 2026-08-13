import Foundation

/// Supported LLM provider types.
///
/// v1 supports only DeepSeek, but the enum is designed for future providers.
public enum LLMProviderType: String, Codable, Sendable, CaseIterable, Identifiable {
    case deepseek

    public var id: String { rawValue }
}

/// Configuration for a single LLM provider, persisted outside the Keychain.
///
/// The actual API key is stored in the Keychain under ``apiKeyReference``; this
/// struct only keeps non-secret settings and the reference name.
public struct LLMProviderConfiguration: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var providerType: LLMProviderType
    public var displayName: String
    public var baseURL: String
    public var model: String
    public var temperature: Double
    public var systemPrompt: String?
    public var maxTokens: Int?
    public var apiKeyReference: String

    public init(
        id: String,
        providerType: LLMProviderType,
        displayName: String,
        baseURL: String,
        model: String,
        temperature: Double,
        systemPrompt: String? = nil,
        maxTokens: Int? = nil,
        apiKeyReference: String
    ) {
        self.id = id
        self.providerType = providerType
        self.displayName = displayName
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.apiKeyReference = apiKeyReference
    }

    /// A DeepSeek configuration with the defaults used in v1.
    public static func deepseekDefault(
        id: String = "deepseek",
        apiKeyReference: String = "all-in-gentle.provider.deepseek.api-key"
    ) -> LLMProviderConfiguration {
        LLMProviderConfiguration(
            id: id,
            providerType: .deepseek,
            displayName: "DeepSeek",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-chat",
            temperature: 0.7,
            apiKeyReference: apiKeyReference
        )
    }
}
