import SwiftUI

/// Native macOS settings pane for configuring the single AI provider.
///
/// v1 supports DeepSeek only, but the picker and model are designed so adding
/// future providers requires no structural changes.
public struct AISettingsView: View {
    private let store: PreferencesStore
    private let keychain: KeychainStore

    @State private var draft: LLMProviderConfiguration?
    @State private var apiKey: String = ""
    @State private var validationMessage: String?
    @State private var testResult: String?
    @State private var isTesting: Bool = false

    public init(
        store: PreferencesStore = PreferencesStore(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.store = store
        self.keychain = keychain
    }

    public var body: some View {
        Group {
            if draft != nil {
                formContent
            } else {
                emptyContent
            }
        }
        .frame(minWidth: 520, maxWidth: 640, minHeight: 360)
        .background(AGColors.background)
        .onAppear {
            Task { @MainActor in
                await load()
            }
        }
    }

    // MARK: - Subviews

    private var emptyContent: some View {
        AGEmptyState(
            systemImage: "brain",
            titleKey: "settings.ai.empty.title",
            messageKey: "settings.ai.empty.message",
            action: (titleKey: "settings.ai.addProvider", action: addProvider)
        )
    }

    private var formContent: some View {
        Form {
            Section(header: sectionHeader("settings.ai.section.provider")) {
                Picker(L("settings.ai.providerType"), selection: providerTypeBinding) {
                    ForEach(LLMProviderType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                TextField(L("settings.ai.displayName"), text: displayNameBinding)

                SecureField(
                    L("settings.ai.apiKey"),
                    text: $apiKey,
                    prompt: Text(L("settings.ai.apiKey.placeholder"))
                )

                Text(L("settings.ai.apiKey.hint"))
                    .font(AGTypography.caption)
                    .foregroundStyle(AGColors.textSecondary)
            }

            Section(header: sectionHeader("settings.ai.section.endpoint")) {
                TextField(L("settings.ai.baseURL"), text: baseURLBinding)
                TextField(L("settings.ai.model"), text: modelBinding)
            }

            Section(header: sectionHeader("settings.ai.section.generation")) {
                LabeledContent(L("settings.ai.temperature")) {
                    HStack(spacing: AGSpacing.xSmall) {
                        Slider(value: temperatureBinding, in: 0...2, step: 0.1)
                            .frame(width: 160)

                        Text(String(format: "%.1f", draft?.temperature ?? 0))
                            .font(AGTypography.monoCaption)
                            .foregroundStyle(AGColors.textSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                TextField(L("settings.ai.maxTokens"), text: maxTokensBinding)
            }

            Section(header: sectionHeader("settings.ai.section.prompt")) {
                TextEditor(text: systemPromptBinding)
                    .frame(minHeight: 80)
            }

            Section {
                HStack(spacing: AGSpacing.small) {
                    AGButton("settings.ai.save", systemImage: "checkmark", variant: .primary) {
                        Task { @MainActor in
                            await save()
                        }
                    }
                    .disabled(draft == nil)

                    AGButton("settings.ai.testConnection", systemImage: "network", variant: .secondary) {
                        Task { @MainActor in
                            await testConnection()
                        }
                    }
                    .disabled(isTesting)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(AGTypography.caption)
                        .foregroundStyle(AGColors.statusError)
                }

                if let testResult {
                    Text(testResult)
                        .font(AGTypography.caption)
                        .foregroundStyle(AGColors.statusLive)
                }
            }
        }
        .formStyle(.grouped)
        .padding(AGSpacing.medium)
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(L(key))
            .font(AGTypography.caption)
            .foregroundStyle(AGColors.textSecondary)
    }

    // MARK: - Bindings

    private var providerTypeBinding: Binding<LLMProviderType> {
        Binding(
            get: { draft?.providerType ?? .deepseek },
            set: { draft?.providerType = $0 }
        )
    }

    private var displayNameBinding: Binding<String> {
        Binding(
            get: { draft?.displayName ?? "" },
            set: { draft?.displayName = $0 }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { draft?.baseURL ?? "" },
            set: { draft?.baseURL = $0 }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { draft?.model ?? "" },
            set: { draft?.model = $0 }
        )
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { draft?.temperature ?? 0.7 },
            set: { draft?.temperature = $0 }
        )
    }

    private var systemPromptBinding: Binding<String> {
        Binding(
            get: { draft?.systemPrompt ?? "" },
            set: { draft?.systemPrompt = $0.isEmpty ? nil : $0 }
        )
    }

    private var maxTokensBinding: Binding<String> {
        Binding(
            get: { draft?.maxTokens.map(String.init) ?? "" },
            set: { draft?.maxTokens = Int($0) }
        )
    }

    // MARK: - Keychain load diagnostics

    /// Maps a keychain `load` outcome to the validation message shown under
    /// the form (spec R5).
    ///
    /// A missing item is not an error: `load` returns `nil` and the API key
    /// field stays empty — the normal "no key yet" state — so no message is
    /// produced. Thrown errors surface a localized diagnostic: the keychain
    /// store wraps every non-not-found failure (including auth/interaction
    /// failures) in ``AllInGentleError/persistenceFailure(_:)``, whose
    /// associated message carries the real diagnostic; any other error falls
    /// back to a generic message.
    static func keychainLoadDiagnostic(for outcome: Result<String?, any Error>) -> String? {
        switch outcome {
        case .success:
            return nil
        case .failure(let error):
            guard let keychainError = error as? AllInGentleError,
                  case .persistenceFailure(let message) = keychainError else {
                return L("settings.ai.error.keychainLoadFailed")
            }
            return message
        }
    }

    // MARK: - Actions

    private func addProvider() {
        draft = .deepseekDefault()
    }

    private func load() async {
        guard let existing = store.llmProviderConfiguration else { return }
        draft = existing
        do {
            if let key = try await keychain.load(key: existing.apiKeyAccount) {
                apiKey = key
            }
        } catch {
            validationMessage = Self.keychainLoadDiagnostic(for: .failure(error))
        }
    }

    private func validate() -> Bool {
        guard var config = draft else { return false }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            validationMessage = L("settings.ai.error.apiKeyRequired")
            return false
        }

        guard let url = URL(string: config.baseURL),
              let scheme = url.scheme,
              scheme == "https" || scheme == "http" else {
            validationMessage = L("settings.ai.error.invalidURL")
            return false
        }

        config.displayName = config.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !config.displayName.isEmpty else {
            validationMessage = L("settings.ai.error.displayNameRequired")
            return false
        }

        config.model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !config.model.isEmpty else {
            validationMessage = L("settings.ai.error.modelRequired")
            return false
        }

        validationMessage = nil
        return true
    }

    private func save() async {
        guard validate(), var config = draft else { return }

        do {
            let account = LLMProviderConfiguration.keychainAccount(for: config.id)
            config.apiKeyReference = account

            config.displayName = config.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            config.baseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            config.model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)

            try await keychain.save(key: account, value: apiKey)

            store.llmProviderConfiguration = config
            draft = config
            testResult = L("settings.ai.save.success")
        } catch {
            validationMessage = error.localizedDescription
            testResult = nil
        }
    }

    private func testConnection() async {
        guard validate() else { return }

        isTesting = true
        defer { isTesting = false }

        // v1 performs local validation only. A future iteration can make an
        // authenticated request to the provider's health/models endpoint.
        testResult = L("settings.ai.test.success")
    }
}
