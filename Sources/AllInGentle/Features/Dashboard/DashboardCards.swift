import SwiftUI

// MARK: - Pure degradation decisions (DC-2/DC-5/DC-6)

/// The battery card is absent from the grid while no `AppleSmartBattery`
/// exists (DC-5); the same predicate gates grid inclusion and hiddenness.
func batteryCardVisible(_ battery: BatterySnapshot?) -> Bool {
    battery != nil
}

/// RAM pressure → badge mapping (DC-2): normal=live, warning=placeholder,
/// critical=error.
func memoryPressureStatus(_ pressure: MemoryPressure) -> AGStatus {
    switch pressure {
    case .normal: return .live
    case .warning: return .placeholder
    case .critical: return .error
    }
}

/// RAM breakdown segments for the memory bar (DC-2): app/cache/wired/compressed;
/// a nil snapshot yields no segments so the bar degrades to its idle state.
func ramSegments(from ram: RAMSnapshot?) -> [MemorySegment] {
    guard let ram else { return [] }
    return [
        MemorySegment(kind: .app, bytes: ram.appBytes),
        MemorySegment(kind: .cache, bytes: ram.cachedBytes),
        MemorySegment(kind: .wired, bytes: ram.wiredBytes),
        MemorySegment(kind: .compressed, bytes: ram.compressedBytes),
    ]
}

/// Service → badge mapping (DC-6): running = live; a poll failure = error;
/// a cleanly stopped service = disabled.
func serviceBadgeStatus(_ status: ServiceStatus) -> AGStatus {
    if status.isRunning { return .live }
    return status.lastError == nil ? .disabled : .error
}

// MARK: - 3.3 Delta helpers (D3)

/// The change between the two newest samples: `last − secondLast`. `nil` when
/// fewer than two samples exist (spec D3 card delta caption).
func latestDelta(_ history: [MetricSample]) -> Double? {
    guard history.count >= 2,
        let last = history.last?.value,
        let previous = history.dropLast().last?.value
    else { return nil }
    return last - previous
}

/// Signed percentage delta caption, e.g. "+3.2%"; `nil` when no delta exists.
func deltaCaption(_ delta: Double?) -> String? {
    guard let delta else { return nil }
    let sign = delta >= 0 ? "+" : ""
    return String(format: "%@%.1f%%", sign, delta)
}

/// Signed transfer-rate delta caption, e.g. "+1.5 MB/s"; `nil` when no delta.
func rateDeltaCaption(_ delta: Double?) -> String? {
    guard let delta else { return nil }
    let sign = delta >= 0 ? "+" : "-"
    return sign + formatRate(abs(delta))
}

// MARK: - Shared card chrome (AG tokens only, DW-6)

/// Localized caption title (secondary) shared by all six cards (D3).
private func cardTitle(_ titleKey: String) -> some View {
    Text(L(titleKey))
        .font(AGTypography.metricCaption)
        .foregroundStyle(AGColors.textSecondary)
}

/// Loading placeholder shown before the first batch completes.
private func cardLoading() -> some View {
    ProgressView().controlSize(.small)
}

/// Empty-state placeholder for unavailable metrics (G-5, DC-7). Defaults to
/// the shared widget copy; the GPU card overrides both keys (DC-3).
private func cardEmpty(
    _ systemImage: String,
    titleKey: String = AGWidgetCopy.emptyTitleKey,
    messageKey: String = AGWidgetCopy.emptyMessageKey
) -> some View {
    AGEmptyState(systemImage: systemImage, titleKey: titleKey, messageKey: messageKey)
}

/// Secondary caption row (swap, cycles, interface, running/total).
private func cardCaption(_ text: String) -> some View {
    Text(text)
        .font(AGTypography.metricCaption)
        .foregroundStyle(AGColors.textSecondary)
}

/// Mono value row (percentages, used/total, rates).
private func cardMono(_ text: String) -> some View {
    Text(text)
        .font(AGTypography.mono)
        .foregroundStyle(AGColors.textPrimary)
}

/// Large metric numeral — the visual anchor of a card (D2/D3), tinted with
/// the metric's semantic color.
private func cardNumeral(_ text: String, color: Color) -> some View {
    Text(text)
        .font(AGTypography.metric)
        .foregroundStyle(color)
}

/// Delta caption beside the numeral; hidden until two samples exist (D3).
@ViewBuilder
private func cardDelta(_ text: String?) -> some View {
    if let text {
        Text(text)
            .font(AGTypography.metricCaption)
            .foregroundStyle(AGColors.textSecondary)
    }
}

// MARK: - DC-1 CPU

/// CPU card: caption title + tinted numeral + sparkline + delta; per-core
/// bars demoted to a slim footer (DC-1, D3).
struct CPUCard: View {
    let phase: DashboardCardPhase
    let cpu: CPUSnapshot?
    let history: [MetricSample]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
                cardTitle("dashboard.card.cpu.title")
                switch phase {
                case .loading:
                    cardLoading()
                case .empty:
                    cardEmpty("chart.xyaxis.line")
                case .content:
                    HStack(alignment: .firstTextBaseline, spacing: AGSpacing.small) {
                        cardNumeral("\(Int((cpu?.total ?? 0).rounded()))%", color: MetricColor.cpu.token)
                        cardDelta(deltaCaption(latestDelta(history)))
                    }
                    AGMiniChart(samples: history, color: MetricColor.cpu.token)
                    AGBarChart(perCoreValues: cpu?.perCore ?? [], color: MetricColor.cpu.token)
                }
            }
        }
    }
}

// MARK: - DC-2 RAM

/// RAM card: caption title + tinted used-% numeral + ramHistory sparkline +
/// delta; memory bar + swap demoted to a slim footer (DC-2, D3).
struct RAMCard: View {
    let phase: DashboardCardPhase
    let ram: RAMSnapshot?
    let history: [MetricSample]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
                cardTitle("dashboard.card.ram.title")
                switch phase {
                case .loading:
                    cardLoading()
                case .empty:
                    cardEmpty("memorychip")
                case .content:
                    if let ram {
                        HStack(alignment: .firstTextBaseline, spacing: AGSpacing.small) {
                            cardNumeral(
                                "\(Int((history.last?.value ?? 0).rounded()))%",
                                color: MetricColor.ram.token)
                            cardDelta(deltaCaption(latestDelta(history)))
                            Spacer()
                            AGStatusBadge(status: memoryPressureStatus(ram.pressure))
                        }
                        AGMiniChart(samples: history, color: MetricColor.ram.token)
                        AGMemoryBar(segments: ramSegments(from: ram))
                        cardCaption(
                            L(
                                "dashboard.card.ram.swap", formatBytes(ram.swapUsedBytes),
                                formatBytes(ram.swapTotalBytes))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - DC-3 GPU

/// GPU card: caption title + tinted numeral + sparkline + delta on Apple
/// Silicon; AGEmptyState "unavailable" otherwise (DC-3, D3).
struct GPUCard: View {
    let phase: DashboardCardPhase
    let gpu: GPUSnapshot?
    let history: [MetricSample]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
                cardTitle("dashboard.card.gpu.title")
                switch phase {
                case .loading:
                    cardLoading()
                case .empty:
                    cardEmpty(
                        "cpu",
                        titleKey: "dashboard.card.gpu.unavailable.title",
                        messageKey: "dashboard.card.gpu.unavailable.message"
                    )
                case .content:
                    HStack(alignment: .firstTextBaseline, spacing: AGSpacing.small) {
                        cardNumeral(
                            "\(Int((gpu?.utilization ?? 0).rounded()))%",
                            color: MetricColor.gpu.token)
                        cardDelta(deltaCaption(latestDelta(history)))
                    }
                    AGMiniChart(samples: history, color: MetricColor.gpu.token)
                }
            }
        }
    }
}

// MARK: - DC-4 Network

/// Network card: caption title + tinted receive-rate numeral + dual-series
/// sparkline + delta; interface and both rates as captions (DC-4, D3).
struct NetworkCard: View {
    let phase: DashboardCardPhase
    let network: NetworkSnapshot?
    let downHistory: [MetricSample]
    let upHistory: [MetricSample]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
                cardTitle("dashboard.card.network.title")
                switch phase {
                case .loading:
                    cardLoading()
                case .empty:
                    cardEmpty("arrow.up.arrow.down")
                case .content:
                    if let network {
                        HStack(alignment: .firstTextBaseline, spacing: AGSpacing.small) {
                            cardNumeral(
                                formatRate(network.receivedBytesPerSec),
                                color: MetricColor.networkDown.token)
                            cardDelta(rateDeltaCaption(latestDelta(downHistory)))
                        }
                        AGNetworkChart(
                            downSamples: downHistory,
                            upSamples: upHistory,
                            downColor: MetricColor.networkDown.token,
                            upColor: MetricColor.networkUp.token)
                        cardCaption(L("dashboard.card.network.interface", network.interfaceName))
                        cardCaption(networkRatesText(network))
                    }
                }
            }
        }
    }
}

/// Localized down/up rate line for the network card (DC-4).
private func networkRatesText(_ network: NetworkSnapshot) -> String {
    L(
        "dashboard.card.network.rates",
        formatRate(network.receivedBytesPerSec),
        formatRate(network.sentBytesPerSec)
    )
}

// MARK: - DC-5 Battery

/// Battery card: gauge + charging badge + cycles; absent while no AppleSmartBattery exists (DC-5).
struct BatteryCard: View {
    let battery: BatterySnapshot?

    var body: some View {
        if let battery {
            DashboardCard {
                VStack(alignment: .leading, spacing: AGSpacing.small) {
                    HStack(spacing: AGSpacing.small) {
                        cardTitle("dashboard.card.battery.title")
                        Spacer()
                        if battery.isCharging {
                            Text(L("dashboard.card.battery.charging"))
                                .font(AGTypography.caption)
                                .foregroundStyle(AGColors.statusLive)
                                .padding(.horizontal, AGSpacing.badgePaddingHorizontal)
                                .padding(.vertical, AGSpacing.badgePaddingVertical)
                                .background(AGColors.statusLive.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: AGSpacing.medium) {
                        AGGauge(value: battery.level, color: MetricColor.battery.token)
                        VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
                            cardMono("\(Int(battery.level.rounded()))%")
                            cardCaption(L("dashboard.card.battery.cycles", battery.cycleCount))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - DC-6 Services

/// Services card: ProcessMonitor statuses + AGStatusBadge + running/total (DC-6);
/// statuses are empty only before the first slow tick (~5s).
struct ServicesCard: View {
    let statuses: [ServiceStatus]

    private var runningCount: Int { statuses.filter(\.isRunning).count }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.small) {
                HStack(spacing: AGSpacing.small) {
                    cardTitle("dashboard.card.services.title")
                    Spacer()
                    if !statuses.isEmpty {
                        cardCaption(L("dashboard.services.running", runningCount, statuses.count))
                    }
                }
                if statuses.isEmpty {
                    cardLoading()
                } else {
                    ForEach(statuses) { status in
                        HStack(spacing: AGSpacing.small) {
                            Text(status.name)
                                .font(AGTypography.body)
                                .foregroundStyle(AGColors.textPrimary)
                            Spacer()
                            AGStatusBadge(status: serviceBadgeStatus(status))
                        }
                    }
                }
            }
        }
    }
}
