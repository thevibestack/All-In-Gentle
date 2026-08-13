import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                messageList
                Divider()
                if let errorMessage = viewModel.errorMessage {
                    AGErrorState(
                        message: errorMessage,
                        retry: { Task { await viewModel.send() } }
                    )
                    .frame(height: 120)
                }
                inputBar
            }
            .navigationTitle(L("chat.title"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: AGSpacing.xSmall) {
                        AGButton("chat.provider", systemImage: "person.crop.circle", variant: .secondary, action: {})
                            .disabled(true)
                        AGStatusBadge(status: .placeholder)
                    }
                }
            }
            .onChange(of: appState.globalSearchQuery) { _, new in
                viewModel.searchQuery = new
            }
        }
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
                    AGEmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        titleKey: "chat.empty.title",
                        messageKey: "chat.empty.message"
                    )
                }

                if viewModel.isStreaming {
                    AGLoadingState(titleKey: "ds.state.loading")
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

    private var inputBar: some View {
        HStack(spacing: AGSpacing.small) {
            AGSearchField(
                text: $viewModel.input,
                placeholderKey: "chat.message",
                commandHintKey: nil
            )

            if viewModel.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: AGSpacing.iconLarge, height: AGSpacing.iconLarge)
            } else {
                AGButton("", systemImage: "arrow.up.circle.fill", variant: .primary) {
                    Task { await viewModel.send() }
                }
                .disabled(
                    viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(AGSpacing.medium)
        .background(AGColors.surface)
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(spacing: 0) {
            if message.role == .assistant {
                AGCard {
                    MarkdownText(message.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            } else {
                Spacer()
                Text(message.content)
                    .font(AGTypography.body)
                    .foregroundStyle(AGColors.accentText)
                    .textSelection(.enabled)
                    .padding(AGSpacing.small)
                    .background(AGColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AGSpacing.cornerRadiusLarge, style: .continuous))
            }
        }
    }
}
