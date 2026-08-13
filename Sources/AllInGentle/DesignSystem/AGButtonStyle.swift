import SwiftUI

/// Visual variant for an All-In-Gentle button.
public enum AGButtonVariant {
    case primary
    case secondary
    case ghost
    case danger
}

/// A reusable button style with tactile spring feedback.
///
/// The style scales the button to `0.98` and reduces opacity slightly while
/// pressed, giving the control a physical push feel. Variants map to the
/// semantic color tokens so every button stays on-palette.
public struct AGButtonStyle: ButtonStyle {
    public let variant: AGButtonVariant
    @Environment(\.isEnabled) private var isEnabled

    public init(variant: AGButtonVariant = .primary) {
        self.variant = variant
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AGTypography.body)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, AGSpacing.buttonPaddingHorizontal)
            .padding(.vertical, AGSpacing.buttonPaddingVertical)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AGSpacing.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AGSpacing.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: variant == .ghost ? 0 : 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1.0) : 0.55)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isEnabled)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .danger:
            return AGColors.accentText
        case .secondary:
            return AGColors.textPrimary
        case .ghost:
            return AGColors.accent
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:
            return AGColors.accent
        case .secondary:
            return AGColors.surfaceSecondary
        case .ghost:
            return Color.clear
        case .danger:
            return AGColors.statusError
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary, .danger:
            return Color.clear
        case .secondary:
            return AGColors.border
        case .ghost:
            return Color.clear
        }
    }
}
