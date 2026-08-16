import Foundation
import Observation

/// View model for the research chat tab with persisted sessions.
///
/// ``ChatViewModel`` manages a list of ``ChatSession`` records backed by
/// ``ChatSessionStore``. It streams assistant responses through ``LLMService``
/// and updates the active session in place so the UI stays reactive.
@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var sessions: [ChatSession] = []
    public var selectedSessionID: String?
    public var searchQuery: String = ""
    public var messageSearchQuery: String = ""
    public var input: String = ""
    public private(set) var isStreaming: Bool = false
    public var errorMessage: String?
    public var projectID: String?

    /// Messages for the currently selected session.
    public var messages: [ChatMessage] {
        selectedSession?.messages ?? []
    }

    /// Sessions filtered by the local sidebar search query.
    public var filteredSessions: [ChatSession] {
        if searchQuery.isEmpty { return sessions }
        return sessions.filter { session in
            session.displayTitle.localizedCaseInsensitiveContains(searchQuery)
                || session.messages.contains {
                    $0.role == .user && $0.content.localizedCaseInsensitiveContains(searchQuery)
                }
        }
    }

    /// Current session messages filtered by the global message search query.
    public var filteredMessages: [ChatMessage] {
        guard let session = selectedSession else { return [] }
        if messageSearchQuery.isEmpty { return session.messages }
        return session.messages.filter {
            $0.content.localizedCaseInsensitiveContains(messageSearchQuery)
        }
    }

    /// Sessions grouped by relative date for the sidebar list.
    public var groupedSessions: [(key: String, sessions: [ChatSession])] {
        let calendar = Calendar.current
        let now = Date()
        let keys = [
            L("chat.sidebar.today"),
            L("chat.sidebar.yesterday"),
            L("chat.sidebar.previous7Days"),
            L("chat.sidebar.older"),
        ]
        var groups: [String: [ChatSession]] = Dictionary(uniqueKeysWithValues: keys.map { ($0, []) })

        for session in filteredSessions {
            let key: String
            if calendar.isDateInToday(session.updatedAt) {
                key = keys[0]
            } else if calendar.isDateInYesterday(session.updatedAt) {
                key = keys[1]
            } else if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now),
                session.updatedAt >= calendar.startOfDay(for: sevenDaysAgo)
            {
                key = keys[2]
            } else {
                key = keys[3]
            }
            groups[key, default: []].append(session)
        }

        return keys.compactMap { key in
            let sessions = groups[key, default: []]
            return sessions.isEmpty ? nil : (key: key, sessions: sessions)
        }
    }

    /// Whether a provider is configured and messages can be sent.
    public var providerAvailable: Bool {
        preferences.llmProviderConfiguration != nil
    }

    /// Whether the current input can be submitted.
    public var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isStreaming
            && providerAvailable
    }

    /// The currently selected session, if any.
    public var selectedSession: ChatSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    private let service: LLMService
    private let store: ChatSessionStore
    private let preferences: PreferencesStore
    private var generationTask: Task<Void, Never>?

    public init(
        service: LLMService = ProviderSwitcher(),
        store: ChatSessionStore = ChatSessionStore(),
        preferences: PreferencesStore = PreferencesStore()
    ) {
        self.service = service
        self.store = store
        self.preferences = preferences
    }

    // MARK: - Loading

    public func loadSessions() async {
        do {
            let loaded = try await store.loadAll()
            sessions = loaded
            if selectedSessionID == nil, let first = sessions.first {
                selectedSessionID = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Session management

    /// Creates a new empty session and selects it.
    public func newSession() {
        let session = ChatSession(
            title: L("chat.session.newTitle"),
            projectID: projectID,
            modelID: preferences.llmProviderConfiguration?.id ?? ""
        )
        Task {
            do {
                let saved = try await store.save(session)
                await MainActor.run {
                    sessions.insert(saved, at: 0)
                    selectedSessionID = saved.id
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Selects a session by id.
    public func selectSession(id: String?) {
        selectedSessionID = id
        errorMessage = nil
    }

    /// Deletes a session and updates selection.
    public func deleteSession(_ session: ChatSession) {
        Task {
            do {
                try await store.delete(session)
                await MainActor.run {
                    sessions.removeAll { $0.id == session.id }
                    if selectedSessionID == session.id {
                        selectedSessionID = sessions.first?.id
                    }
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Renames a session.
    public func renameSession(_ session: ChatSession, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                var updated = session
                updated.title = trimmed
                let saved = try await store.save(updated)
                await MainActor.run {
                    if let index = sessions.firstIndex(where: { $0.id == saved.id }) {
                        sessions[index] = saved
                    }
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Removes all messages from a session without deleting it.
    public func clearSession(_ session: ChatSession) {
        Task {
            do {
                let cleared = try await store.clearMessages(session)
                await MainActor.run {
                    if let index = sessions.firstIndex(where: { $0.id == cleared.id }) {
                        sessions[index] = cleared
                    }
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Duplicates a session and selects the copy.
    public func duplicateSession(_ session: ChatSession) {
        Task {
            do {
                let copy = try await store.duplicate(session)
                await MainActor.run {
                    sessions.insert(copy, at: 0)
                    selectedSessionID = copy.id
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Streaming

    /// Stops the active generation and keeps any partial assistant message.
    public func stopGeneration() {
        generationTask?.cancel()
    }

    /// Sends the user's current input and streams the assistant reply into
    /// the selected session, creating a session automatically if needed.
    public func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session = await prepareUserMessage(text: text) else { return }
        await streamResponse(for: session)
    }

    /// Re-streams the last persisted user message of the selected session.
    ///
    /// Never appends or persists a new user message. No-op when no provider
    /// is configured or no persisted user message exists.
    public func retryLastSend() async {
        guard !isStreaming, providerAvailable else {
            if !providerAvailable {
                errorMessage = L("chat.error.noProvider")
            }
            return
        }
        guard let session = selectedSession,
              session.messages.last(where: { $0.role == .user }) != nil else { return }
        errorMessage = nil
        isStreaming = true
        await streamResponse(for: session)
    }

    // MARK: - Private streaming helpers

    /// Persists the user's trimmed input into the selected session, creating
    /// one automatically if needed, and returns the session ready to stream.
    private func prepareUserMessage(text: String) async -> ChatSession? {
        guard !text.isEmpty, !isStreaming, providerAvailable else {
            if !text.isEmpty, !providerAvailable {
                errorMessage = L("chat.error.noProvider")
            }
            return nil
        }

        errorMessage = nil
        isStreaming = true
        input = ""

        if selectedSessionID == nil {
            await createSessionForSend()
        }

        guard var session = selectedSession else {
            isStreaming = false
            return nil
        }

        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text
        )
        session.messages.append(userMessage)

        do {
            session = try await store.save(session)
            updateSession(session)
        } catch {
            errorMessage = error.localizedDescription
            isStreaming = false
            return nil
        }

        return session
    }

    /// Streams the assistant reply for the given session, finalizing it by the
    /// session id captured before the generation task starts.
    private func streamResponse(for session: ChatSession) async {
        let sessionID = session.id
        var assistantMessage: ChatMessage?
        var responseText = ""

        generationTask = Task { [weak self] in
            // Weak capture only: a top-level `guard let self` would re-retain
            // the view model for the whole task and keep it alive while the
            // stream hangs. Copy the dependency out, then access `self`
            // per-call so the task holds the view model only momentarily.
            guard let service = self?.service else { return }
            do {
                let stream = try await service.stream(messages: session.messages)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let delta = chunk.textDelta {
                        responseText += delta
                        if assistantMessage == nil {
                            assistantMessage = ChatMessage(
                                id: UUID().uuidString,
                                role: .assistant,
                                content: responseText
                            )
                            if let message = assistantMessage {
                                self?.appendOrUpdateMessage(in: sessionID, message: message)
                            }
                        } else {
                            assistantMessage?.content = responseText
                            if let message = assistantMessage {
                                self?.appendOrUpdateMessage(in: sessionID, message: message)
                            }
                        }
                    }
                    if chunk.finishReason != nil {
                        break
                    }
                }
                await self?.finalizeSession(sessionID: sessionID, assistantMessage: assistantMessage)
            } catch is CancellationError {
                await self?.finalizeSession(sessionID: sessionID, assistantMessage: assistantMessage)
            } catch {
                await self?.removeEmptyAssistantMessage(sessionID: sessionID, assistantMessage: assistantMessage)
                await MainActor.run { self?.errorMessage = error.localizedDescription }
            }
            await MainActor.run {
                self?.isStreaming = false
                self?.generationTask = nil
            }
        }

        // Deliberately not awaited: an async method's frame retains `self` for
        // the whole call, so `await generationTask?.value` would keep the view
        // model alive while the stream is in flight, defeating the weak-capture
        // contract above. Callers observe completion via `isStreaming`.
    }

    // MARK: - Private helpers

    private func createSessionForSend() async {
        let session = ChatSession(
            title: "",
            projectID: projectID,
            modelID: preferences.llmProviderConfiguration?.id ?? ""
        )
        do {
            let saved = try await store.save(session)
            await MainActor.run {
                sessions.insert(saved, at: 0)
                selectedSessionID = saved.id
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    private func updateSession(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    private func appendOrUpdateMessage(in sessionID: String, message: ChatMessage) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = sessions[sessionIndex]
        if let messageIndex = session.messages.firstIndex(where: { $0.id == message.id }) {
            session.messages[messageIndex] = message
        } else {
            session.messages.append(message)
        }
        session.updatedAt = Date()
        sessions[sessionIndex] = session
    }

    @MainActor
    private func finalizeSession(sessionID: String, assistantMessage: ChatMessage?) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var finalSession = sessions[sessionIndex]
        guard let assistantMessage else { return }
        if let index = finalSession.messages.lastIndex(where: { $0.id == assistantMessage.id }) {
            finalSession.messages[index] = assistantMessage
        } else {
            finalSession.messages.append(assistantMessage)
        }
        do {
            finalSession = try await store.save(finalSession)
            updateSession(finalSession)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func removeEmptyAssistantMessage(sessionID: String, assistantMessage: ChatMessage?) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var finalSession = sessions[sessionIndex]
        if let assistantMessage {
            finalSession.messages.removeAll { $0.id == assistantMessage.id && $0.content.isEmpty }
        }
        do {
            finalSession = try await store.save(finalSession)
            updateSession(finalSession)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
