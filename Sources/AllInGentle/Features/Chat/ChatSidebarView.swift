import SwiftUI

struct ChatSidebarView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
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
}
