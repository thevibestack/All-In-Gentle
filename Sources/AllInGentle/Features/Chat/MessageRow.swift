import SwiftUI

struct MessageRow: View {
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
