import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                Divider()
                inputBar
            }
            .navigationTitle(L("chat.title"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    placeholderButton(title: L("chat.provider"))
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List(viewModel.messages) { message in
                MessageRow(message: message)
                    .id(message.id)
            }
            .listStyle(.plain)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let id = viewModel.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .overlay {
                if viewModel.messages.isEmpty {
                    Text(L("chat.start"))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField(L("chat.message"), text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($isInputFocused)

            Button(action: { Task { await viewModel.send() } }) {
                if viewModel.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(
                viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isStreaming
            )
        }
        .padding()
    }

    private func placeholderButton(title: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Text(title)
                InteractionStateBadge(state: .placeholder)
            }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                Text(message.content)
                    .textSelection(.enabled)
                Spacer()
            } else {
                Spacer()
                Text(message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }
}
