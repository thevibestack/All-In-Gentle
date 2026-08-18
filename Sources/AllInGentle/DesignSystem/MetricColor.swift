import SwiftUI

/// Semantic color token per dashboard metric (spec D1).
///
/// CPU keeps the single accent hue; the other metrics reuse the four status
/// hues — no new colors, so the max-one-accent rule is preserved. Tokens are
/// dynamic (light/dark) because they delegate to `AGColors` dynamic providers.
public enum MetricColor: Sendable, CaseIterable {
    case cpu
    case gpu
    case ram
    case networkDown
    case networkUp
    case battery

    /// The AGColors token backing this metric. Series and numerals must use
    /// this token instead of shared accent/status colors directly.
    public var token: Color {
        switch self {
        case .cpu:
            return AGColors.accent
        case .gpu:
            return AGColors.statusLive
        case .ram:
            return AGColors.statusPlaceholder
        case .networkDown:
            return AGColors.statusLive
        case .networkUp:
            return AGColors.statusPlaceholder
        case .battery:
            return AGColors.statusDisabled
        }
    }
}
