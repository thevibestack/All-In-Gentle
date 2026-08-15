import SwiftUI

struct ChatToolbarView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var renameText: String
    @Binding var showingRenameAlert: Bool
    @Binding var showingDeleteConfirmation: Bool
    var focusInput: () -> Void

    var body: some View {
        HStack(spacing: AGSpacing.small) {
            Button {
                focusInput()
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
}
