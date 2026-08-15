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
            ChatSidebarView(viewModel: viewModel)
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

    private var mainArea: some View {
        VStack(spacing: 0) {
            ChatToolbarView(
                viewModel: viewModel,
                renameText: $renameText,
                showingRenameAlert: $showingRenameAlert,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                focusInput: { inputFocused = true }
            )
            Divider()
            ChatMessageListView(
                viewModel: viewModel,
                onPromptTapped: { prompt in
                    viewModel.input = prompt
                    inputFocused = true
                }
            )
            Divider()
            if let errorMessage = viewModel.errorMessage {
                AGErrorState(
                    systemImage: "exclamationmark.triangle",
                    message: errorMessage,
                    retry: {
                        Task { await viewModel.send() }
                    }
                )
                .frame(height: 120)
            }
            ChatInputBarView(viewModel: viewModel, inputFocused: $inputFocused)
        }
        .background(AGColors.background)
    }
}
