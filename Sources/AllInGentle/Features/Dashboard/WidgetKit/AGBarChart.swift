import Charts
import SwiftUI

/// Clamps a per-core usage percentage into the 0...100 bar domain (DW-2).
func barChartHeight(_ value: Double) -> Double {
    min(max(value, 0), 100)
}

/// The bar chart is hidden entirely while there is no per-core data (DW-2).
func barChartShowsBars(_ values: [Double]) -> Bool {
    !values.isEmpty
}

/// Per-core usage bars scaled 0...100%, spec DW-2.
public struct AGBarChart: View {
    public let perCoreValues: [Double]
    public let color: Color

    public init(perCoreValues: [Double], color: Color = AGColors.statusLive) {
        self.perCoreValues = perCoreValues
        self.color = color
    }

    public var barColor: Color { color }

    public var body: some View {
        if barChartShowsBars(perCoreValues) {
            Chart {
                ForEach(Array(perCoreValues.enumerated()), id: \.offset) { index, value in
                    BarMark(
                        x: .value("Core", index),
                        y: .value("Usage", barChartHeight(value)),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(barColor)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: AGSpacing.xLarge * 3)
        }
    }
}
