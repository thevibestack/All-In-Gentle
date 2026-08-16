import SwiftUI

/// Status values supported by the design-system badge.
public enum AGStatus: String, CaseIterable, Sendable {
    case live
    case placeholder
    case disabled
    case error
}

extension AGStatus {
    public var catalogKey: String {
        switch self {
        case .live:
            return "badge.live"
        case .placeholder:
            return "badge.placeholder"
        case .disabled:
            return "badge.disabled"
        case .error:
            return "ds.badge.error"
        }
    }

    public var label: String {
        L(catalogKey)
    }

    public var tint: Color {
        switch self {
        case .live:
            return AGColors.statusLive
        case .placeholder:
            return AGColors.statusPlaceholder
        case .disabled:
            return AGColors.statusDisabled
        case .error:
            return AGColors.statusError
        }
    }
}

/// A compact status badge using semantic color tokens.
public struct AGStatusBadge: View {
    public let status: AGStatus

    public init(status: AGStatus) {
        self.status = status
    }

    public var body: some View {
        Text(status.label)
            .font(AGTypography.caption)
            .foregroundStyle(status.tint)
            .padding(.horizontal, AGSpacing.badgePaddingHorizontal)
            .padding(.vertical, AGSpacing.badgePaddingVertical)
            .background(status.tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
