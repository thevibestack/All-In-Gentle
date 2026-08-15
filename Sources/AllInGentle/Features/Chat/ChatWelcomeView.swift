import SwiftUI

struct ChatWelcomeView: View {
    let onPromptTapped: (String) -> Void

    var body: some View {
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
                            onPromptTapped(prompt)
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
}
