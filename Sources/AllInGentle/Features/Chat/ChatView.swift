import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @Environment(AppState.self) private var appState
    @FocusState private var inputFocused: Bool
    @State private var showingDeleteConfirmation = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)
            mainArea
        }
        .navigationTitle(L("chat.title"))
        .onChange(of: appState.selectedProjectPath) { _, new in
            viewModel.projectID = new
        }
        .onChange(of: appState.globalSearchQuery) { _, new in
            viewModel.messageSearchQuery = new
        }
        .task {
            await viewModel.loadSessions()
        }
        .alert(L("chat.toolbar.rename"), isPresented: $showingRenameAlert) {
            TextField(L("chat.toolbar.rename.placeholder"), text: $renameText)
            Button(L("chat.toolbar.rename.save")) {
                if let session = viewModel.selectedSession {
                    viewModel.renameSession(session, newTitle: renameText)
                }
            }
            Button(L("chat.toolbar.rename.cancel"), role: .cancel) {}
        } message: {
            Text(L("chat.toolbar.rename.message"))
        }
        .confirmationDialog(
            L("chat.toolbar.delete.confirmationTitle"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("chat.toolbar.delete"), role: .destructive) {
                if let session = viewModel.selectedSession {
                    viewModel.deleteSession(session)
                }
            }
            Button(L("chat.toolbar.delete.cancel"), role: .cancel) {}
        } message: {
            Text(L("chat.toolbar.delete.confirmationMessage"))
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
            sessionList
        }
    }

    private var sidebarHeader: some View {
        VStack(spacing: AGSpacing.small) {
            HStack {
                Text(L("chat.title"))
                    .font(AGTypography.headline)
                Spacer()
                Button {
                    viewModel.newSession()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(AGTypography.body)
                        .foregroundStyle(AGColors.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .help(L("chat.sidebar.newChat"))
            }
            AGSearchField(
                text: $viewModel.searchQuery,
                placeholderKey: "chat.sidebar.search",
                commandHintKey: nil
            )
        }
        .padding(AGSpacing.medium)
        .background(AGColors.surface)
    }

    private var sessionList: some View {
        List(selection: $viewModel.selectedSessionID) {
            if viewModel.filteredSessions.isEmpty {
                AGEmptyState(
                    systemImage: "bubble.left.and.bubble.right",
                    titleKey: "chat.empty.noSession.title",
                    messageKey: "chat.empty.noSession.message",
                    action: (titleKey: "chat.sidebar.newChat", action: { viewModel.newSession() })
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } else {
                ForEach(viewModel.groupedSessions, id: \.key) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            sessionRow(session: session)
                                .tag(session.id)
                                .listRowInsets(EdgeInsets(top: AGSpacing.xxSmall, leading: AGSpacing.small, bottom: AGSpacing.xxSmall, trailing: AGSpacing.small))
                        }
                    } header: {
                        sectionHeader(title: group.key)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(AGTypography.caption)
            .foregroundStyle(AGColors.textSecondary)
            .textCase(nil)
            .padding(.horizontal, AGSpacing.small)
            .padding(.top, AGSpacing.small)
    }

    private func sessionRow(session: ChatSession) -> some View {
        HStack(spacing: AGSpacing.xSmall) {
            VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
                Text(session.displayTitle)
                    .font(AGTypography.body)
                    .foregroundStyle(AGColors.textPrimary)
                    .lineLimit(1)
                Text(session.updatedAt, style: .relative)
                    .font(AGTypography.caption)
                    .foregroundStyle(AGColors.textSecondary)
            }
            Spacer(minLength: 0)
            if session.projectID != nil {
                Image(systemName: "folder.fill")
                    .font(AGTypography.caption)
                    .foregroundStyle(AGColors.accent)
                    .help(L("chat.project.badge"))
            }
        }
        .padding(.vertical, AGSpacing.xSmall)
    }

    // MARK: - Main area

    private var mainArea: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            messageList
            Divider()
            if let errorMessage = viewModel.errorMessage {
                AGErrorState(
                    systemImage: "exclamationmark.triangle",
                    message: errorMessage,
                    retry: {
                        Task { await viewModel.retryLastSend() }
                    }
                )
                .frame(height: 120)
            }
            inputBar
        }
        .background(AGColors.background)
    }

    private var toolbar: some View {
        HStack(spacing: AGSpacing.small) {
            Button {
                inputFocused = true
            } label: {
                EmptyView()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .opacity(0)
            .frame(width: 0, height: 0)

            if let session = viewModel.selectedSession {
                Text(session.displayTitle)
                    .font(AGTypography.headline)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: AGSpacing.xSmall) {
                    Image(systemName: "cpu")
                        .font(AGTypography.caption)
                        .foregroundStyle(AGColors.textSecondary)
                    Text(viewModel.providerAvailable ? L("chat.toolbar.status.ready") : L("chat.toolbar.status.disabled"))
                        .font(AGTypography.caption)
                        .foregroundStyle(viewModel.providerAvailable ? AGColors.statusLive : AGColors.statusDisabled)
                }
                Menu {
                    Button(L("chat.toolbar.rename")) {
                        renameText = session.title
                        showingRenameAlert = true
                    }
                    Button(L("chat.toolbar.duplicate")) {
                        viewModel.duplicateSession(session)
                    }
                    Button(L("chat.toolbar.clear")) {
                        viewModel.clearSession(session)
                    }
                    Divider()
                    Button(L("chat.toolbar.delete")) {
                        showingDeleteConfirmation = true
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(AGTypography.body)
                        .foregroundStyle(AGColors.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: AGSpacing.iconLarge)
            } else {
                Spacer()
            }
        }
        .padding(AGSpacing.medium)
        .background(AGColors.surface)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack {
                List(viewModel.filteredMessages) { message in
                    MessageRow(message: message)
                        .id(message.id)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: AGSpacing.xxSmall, leading: AGSpacing.medium, bottom: AGSpacing.xxSmall, trailing: AGSpacing.medium))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                if viewModel.filteredMessages.isEmpty {
                    if viewModel.selectedSession == nil {
                        AGEmptyState(
                            systemImage: "bubble.left.and.bubble.right",
                            titleKey: "chat.empty.noSession.title",
                            messageKey: "chat.empty.noSession.message",
                            action: (titleKey: "chat.sidebar.newChat", action: { viewModel.newSession() })
                        )
                    } else if viewModel.messages.isEmpty {
                        welcomeCard
                    } else {
                        AGEmptyState(
                            systemImage: "magnifyingglass",
                            titleKey: "chat.empty.search.title",
                            messageKey: "chat.empty.search.message"
                        )
                    }
                }

                if viewModel.isStreaming {
                    AGLoadingState(titleKey: "chat.state.streaming")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(AGSpacing.medium)
                }
            }
            .onChange(of: viewModel.filteredMessages.count) { _, _ in
                if let id = viewModel.filteredMessages.last?.id {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGSpacing.small) {
                Text(L("chat.main.welcome.title"))
                    .font(AGTypography.headline)
                    .foregroundStyle(AGColors.textPrimary)
                Text(L("chat.main.welcome.message"))
                    .font(AGTypography.body)
                    .foregroundStyle(AGColors.textSecondary)

                Text(L("chat.main.suggestedPrompts.title"))
                    .font(AGTypography.caption)
                    .foregroundStyle(AGColors.textSecondary)
                    .padding(.top, AGSpacing.small)

                VStack(spacing: AGSpacing.small) {
                    ForEach(suggestedPrompts, id: \.self) { prompt in
                        Button {
                            viewModel.input = prompt
                            inputFocused = true
                        } label: {
                            HStack {
                                Text(prompt)
                                    .font(AGTypography.body)
                                    .foregroundStyle(AGColors.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(AGSpacing.small)
                            .background(AGColors.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AGSpacing.cornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AGSpacing.cornerRadius, style: .continuous)
                                    .stroke(AGColors.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(AGSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var suggestedPrompts: [String] {
        [
            L("chat.suggested.1"),
            L("chat.suggested.2"),
            L("chat.suggested.3")
        ]
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: AGSpacing.small) {
            ZStack(alignment: .leading) {
                TextEditor(text: $viewModel.input)
                    .font(AGTypography.body)
                    .foregroundStyle(AGColors.textPrimary)
                    .frame(minHeight: AGSpacing.rowHeightLarge, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(AGSpacing.small)
                    .focused($inputFocused)

                if viewModel.input.isEmpty && !inputFocused {
                    Text(L("chat.input.placeholder"))
                        .font(AGTypography.body)
                        .foregroundStyle(AGColors.textSecondary)
                        .padding(AGSpacing.small)
                        .padding(.leading, AGSpacing.xxSmall)
                        .allowsHitTesting(false)
                }
            }
            .background(AGColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AGSpacing.cornerRadius, style: .continuous))

            if viewModel.isStreaming {
                Button {
                    viewModel.stopGeneration()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: AGSpacing.iconLarge))
                        .foregroundStyle(AGColors.statusError)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: AGSpacing.iconLarge))
                        .foregroundStyle(viewModel.canSend ? AGColors.accent : AGColors.statusDisabled)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(AGSpacing.medium)
        .background(AGColors.surface)
    }
}
