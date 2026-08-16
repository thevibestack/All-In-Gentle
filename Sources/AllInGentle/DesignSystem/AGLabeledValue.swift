import SwiftUI

/// A caption label above a body value rendered with monospaced digits.
///
/// Shared by ServicesView and SessionCleanerView so numeric values (PID,
/// port, uptime, token counts, cost) align consistently.
public struct AGLabeledValue: View {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
            Text(label)
                .font(AGTypography.caption)
                .foregroundStyle(AGColors.textSecondary)
            Text(value)
                .font(AGTypography.body)
                .foregroundStyle(AGColors.textPrimary)
                .monospacedDigit()
        }
    }
}
