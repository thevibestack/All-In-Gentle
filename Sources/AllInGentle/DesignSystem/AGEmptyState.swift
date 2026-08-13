import SwiftUI

/// Reusable empty-state view: left-aligned content with asymmetric spacing.
public struct AGEmptyState: View {
    public let systemImage: String
    public let titleKey: String
    public let messageKey: String
    public let action: (titleKey: String, action: () -> Void)?

    public init(
        systemImage: String,
        titleKey: String,
        messageKey: String,
        action: (titleKey: String, action: () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: AGSpacing.xxLarge, weight: .light))
                .foregroundStyle(AGColors.textSecondary)

            Text(L(titleKey))
                .font(AGTypography.headline)
                .foregroundStyle(AGColors.textPrimary)

            Text(L(messageKey))
                .font(AGTypography.body)
                .foregroundStyle(AGColors.textSecondary)
                .lineLimit(2)

            if let action {
                AGButton(action.titleKey, systemImage: "plus", variant: .secondary, action: action.action)
                    .padding(.top, AGSpacing.xSmall)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, AGSpacing.xLarge)
        .padding(.leading, AGSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
