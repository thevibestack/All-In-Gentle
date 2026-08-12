import SwiftUI

public enum InteractionState: String, CaseIterable, Sendable {
    case live
    case placeholder
    case disabled
}

extension InteractionState {
    public var catalogKey: String {
        switch self {
        case .live:
            return "badge.live"
        case .placeholder:
            return "badge.placeholder"
        case .disabled:
            return "badge.disabled"
        }
    }

    public var label: String {
        L(catalogKey)
    }

    public var tint: Color {
        switch self {
        case .live:
            return .green
        case .placeholder:
            return .orange
        case .disabled:
            return .secondary
        }
    }
}

public struct InteractionStateBadge: View {
    let state: InteractionState

    public init(state: InteractionState) {
        self.state = state
    }

    public var body: some View {
        Text(state.label)
            .font(.caption2)
            .foregroundStyle(state.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(state.tint.opacity(0.15))
            .clipShape(Capsule())
    }
}
