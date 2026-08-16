import SwiftUI

struct ChatMessageListView: View {
    @Bindable var viewModel: ChatViewModel
    var onPromptTapped: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                List(viewModel.filteredMessages) { message in
                    MessageRow(message: message)
                        .id(message.id)
                        .listRowBackground(Color.clear)
                        .listRowInsets(
                            EdgeInsets(
                                top: AGSpacing.xxSmall, leading: AGSpacing.medium, bottom: AGSpacing.xxSmall,
                                trailing: AGSpacing.medium))
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
                        ChatWelcomeView(onPromptTapped: onPromptTapped)
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
}
