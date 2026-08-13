import SwiftUI

/// Reusable error-state view with a retry action.
public struct AGErrorState: View {
    public let systemImage: String
    public let titleKey: String
    public let messageKey: String
    public let messageOverride: String?
    public let retryTitleKey: String
    public let retry: (() -> Void)?

    public init(
        systemImage: String = "exclamationmark.triangle",
        titleKey: String = "ds.state.error.title",
        messageKey: String = "ds.state.error.message",
        retryTitleKey: String = "ds.button.retry",
        retry: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.messageOverride = nil
        self.retryTitleKey = retryTitleKey
        self.retry = retry
    }

    /// Creates an error state with a dynamic, runtime message string.
    public init(
        systemImage: String = "exclamationmark.triangle",
        titleKey: String = "ds.state.error.title",
        message: String,
        retryTitleKey: String = "ds.button.retry",
        retry: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.titleKey = titleKey
        self.messageKey = ""
        self.messageOverride = message
        self.retryTitleKey = retryTitleKey
        self.retry = retry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: AGSpacing.xxLarge, weight: .light))
                .foregroundStyle(AGColors.statusError)

            Text(L(titleKey))
                .font(AGTypography.headline)
                .foregroundStyle(AGColors.textPrimary)

            Text(messageOverride ?? L(messageKey))
                .font(AGTypography.body)
                .foregroundStyle(AGColors.textSecondary)
                .lineLimit(3)

            if let retry {
                AGButton(retryTitleKey, systemImage: "arrow.clockwise", variant: .secondary, action: retry)
                    .padding(.top, AGSpacing.xSmall)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, AGSpacing.xLarge)
        .padding(.leading, AGSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
