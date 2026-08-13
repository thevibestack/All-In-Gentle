import SwiftUI

/// A convenience button that applies the design-system style and variant.
public struct AGButton: View {
    public let titleKey: String
    public let systemImage: String?
    public let variant: AGButtonVariant
    public let action: () -> Void

    public init(
        _ titleKey: String,
        systemImage: String? = nil,
        variant: AGButtonVariant = .primary,
        action: @escaping () -> Void
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.variant = variant
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AGSpacing.xSmall) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .font(AGTypography.caption)
                }
                Text(L(titleKey))
            }
        }
        .buttonStyle(AGButtonStyle(variant: variant))
    }
}
