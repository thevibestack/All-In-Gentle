import Charts
import SwiftUI

/// Shared Y-domain for chart widgets. Returns `nil` when the series is empty
/// (the widget renders its empty state instead); otherwise a range spanning
/// every value, padded so a single-sample or flat series still has a
/// non-zero height and never divides by zero (spec DW-1/5).
func chartYDomain(_ samples: [MetricSample]) -> ClosedRange<Double>? {
    guard let minValue = samples.map(\.value).min(),
        let maxValue = samples.map(\.value).max()
    else { return nil }
    if minValue == maxValue {
        let pad = max(abs(minValue) * 0.1, 1)
        return (minValue - pad)...(maxValue + pad)
    }
    return minValue...maxValue
}

/// Localization keys shared by all dashboard widgets. The string values are
/// added in the resources pass (task 5.6); `L()` falls back to the key until
/// then, so no widget hardcodes user-facing copy (spec G-1).
enum AGWidgetCopy {
    static let emptyTitleKey = "dashboard.widgets.empty.title"
    static let emptyMessageKey = "dashboard.widgets.empty.message"
}

/// History line/area chart for CPU/GPU series, spec DW-1.
public struct AGLineChart: View {
    public let samples: [MetricSample]

    public init(samples: [MetricSample]) {
        self.samples = samples
    }

    public var lineColor: Color { AGColors.accent }
    public var areaColor: Color { AGColors.accent.opacity(0.15) }

    public var body: some View {
        if samples.isEmpty {
            AGEmptyState(
                systemImage: "chart.xyaxis.line",
                titleKey: AGWidgetCopy.emptyTitleKey,
                messageKey: AGWidgetCopy.emptyMessageKey
            )
        } else if let yDomain = chartYDomain(samples) {
            Chart {
                ForEach(samples) { sample in
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.value)
                    )
                    .foregroundStyle(areaColor)
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.value)
                    )
                    .foregroundStyle(lineColor)
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: AGSpacing.xLarge * 3)
        }
    }
}

/// Compact sparkline for tight spaces, spec DW-1.
public struct AGMiniChart: View {
    public let samples: [MetricSample]

    public init(samples: [MetricSample]) {
        self.samples = samples
    }

    public var lineColor: Color { AGColors.accent }

    public var body: some View {
        if samples.isEmpty {
            AGEmptyState(
                systemImage: "chart.xyaxis.line",
                titleKey: AGWidgetCopy.emptyTitleKey,
                messageKey: AGWidgetCopy.emptyMessageKey
            )
        } else if let yDomain = chartYDomain(samples) {
            Chart {
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.value)
                    )
                    .foregroundStyle(lineColor)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: AGSpacing.xLarge)
        }
    }
}
