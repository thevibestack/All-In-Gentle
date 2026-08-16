import SwiftUI

struct ChatInputBarView: View {
    @Bindable var viewModel: ChatViewModel
    var inputFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .bottom, spacing: AGSpacing.small) {
            ZStack(alignment: .leading) {
                TextEditor(text: $viewModel.input)
                    .font(AGTypography.body)
                    .foregroundStyle(AGColors.textPrimary)
                    .frame(minHeight: AGSpacing.rowHeightLarge, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(AGSpacing.small)
                    .focused(inputFocused)

                if viewModel.input.isEmpty && !inputFocused.wrappedValue {
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
                .accessibilityLabel(L("chat.toolbar.stop"))
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
                .accessibilityLabel(L("chat.toolbar.send"))
                .disabled(!viewModel.canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(AGSpacing.medium)
        .background(AGColors.surface)
    }
}
