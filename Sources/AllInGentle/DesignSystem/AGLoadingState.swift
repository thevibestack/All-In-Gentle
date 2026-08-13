import SwiftUI

/// Reusable loading-state view with a determinate progress indicator and label.
public struct AGLoadingState: View {
    public let titleKey: String

    public init(titleKey: String = "ds.state.loading") {
        self.titleKey = titleKey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.medium) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.regular)
                .frame(width: AGSpacing.iconLarge, height: AGSpacing.iconLarge)

            Text(L(titleKey))
                .font(AGTypography.body)
                .foregroundStyle(AGColors.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(.top, AGSpacing.xLarge)
        .padding(.leading, AGSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
