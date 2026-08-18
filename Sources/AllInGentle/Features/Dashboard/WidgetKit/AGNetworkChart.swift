import Charts
import SwiftUI

/// Dual-series throughput chart (received/sent), spec DW-5.
public struct AGNetworkChart: View {
    public let downSamples: [MetricSample]
    public let upSamples: [MetricSample]
    public let downColor: Color
    public let upColor: Color

    public init(
        downSamples: [MetricSample],
        upSamples: [MetricSample],
        downColor: Color = AGColors.statusLive,
        upColor: Color = AGColors.statusPlaceholder
    ) {
        self.downSamples = downSamples
        self.upSamples = upSamples
        self.downColor = downColor
        self.upColor = upColor
    }

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
            .animation(.easeOut(duration: 0.25), value: downSamples)
            .animation(.easeOut(duration: 0.25), value: upSamples)
        }
    }
}
