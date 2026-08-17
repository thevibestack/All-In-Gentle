import SwiftUI

/// Maps a 0...100 percent level to a 0...1 gauge value. `nil` (no data yet)
/// shows an empty gauge at 0; out-of-range values clamp (DW-4).
func gaugeProgress(fromPercent value: Double?) -> Double {
    guard let value else { return 0 }
    return min(max(value / 100, 0), 1)
}

/// Dial-style gauge via SwiftUI's `accessoryCircularCapacity`, spec DW-4.
public struct AGGauge: View {
    public let value: Double?

    public init(value: Double?) {
        self.value = value
    }

    public var gaugeColor: Color { AGColors.accent }

    private var progress: Double { gaugeProgress(fromPercent: value) }

    public var body: some View {
        Gauge(value: progress) {
            EmptyView()
        } currentValueLabel: {
            Text(progress, format: .percent)
                .font(AGTypography.monoCaption)
                .foregroundStyle(AGColors.textSecondary)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(gaugeColor)
        .frame(width: AGSpacing.xxLarge, height: AGSpacing.xxLarge)
    }
}
