import Charts
import SwiftUI

/// Dual-series throughput chart (received/sent), spec DW-5.
public struct AGNetworkChart: View {
    public let downSamples: [MetricSample]
    public let upSamples: [MetricSample]

    public init(downSamples: [MetricSample], upSamples: [MetricSample]) {
        self.downSamples = downSamples
        self.upSamples = upSamples
    }

    public var downColor: Color { AGColors.statusLive }
    public var upColor: Color { AGColors.statusPlaceholder }

    public var body: some View {
        if downSamples.isEmpty && upSamples.isEmpty {
            AGEmptyState(
                systemImage: "arrow.up.arrow.down",
                titleKey: AGWidgetCopy.emptyTitleKey,
                messageKey: AGWidgetCopy.emptyMessageKey
            )
        } else if let yDomain = chartYDomain(downSamples + upSamples) {
            Chart {
                ForEach(downSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Received", sample.value)
                    )
                    .foregroundStyle(downColor)
                }
                ForEach(upSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Sent", sample.value)
                    )
                    .foregroundStyle(upColor)
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: AGSpacing.xLarge * 3)
        }
    }
}
