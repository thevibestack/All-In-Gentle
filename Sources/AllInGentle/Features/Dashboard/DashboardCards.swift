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

// MARK: - Shared card chrome (AG tokens only, DW-6)

/// Localized card title (G-1) shared by all six cards.
private func cardTitle(_ titleKey: String) -> some View {
    Text(L(titleKey))
        .font(AGTypography.headline)
        .foregroundStyle(AGColors.textPrimary)
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
        .font(AGTypography.caption)
        .foregroundStyle(AGColors.textSecondary)
}

/// Mono value row (percentages, used/total, rates).
private func cardMono(_ text: String) -> some View {
    Text(text)
        .font(AGTypography.mono)
        .foregroundStyle(AGColors.textPrimary)
}

// MARK: - DC-1 CPU

/// CPU card: gauge + line history + per-core bars (DC-1).
struct CPUCard: View {
    let phase: DashboardCardPhase
    let cpu: CPUSnapshot?
    let history: [MetricSample]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.small) {
                cardTitle("dashboard.card.cpu.title")
                switch phase {
                case .loading:
                    cardLoading()
                case .empty:
                    cardEmpty("chart.xyaxis.line")
                case .content:
                    HStack(spacing: AGSpacing.medium) {
                        AGGauge(value: cpu?.total)
                        cardMono("\(Int((cpu?.total ?? 0).rounded()))%")
                    }
                    AGLineChart(samples: history)
                    AGBarChart(perCoreValues: cpu?.perCore ?? [])
                }
            }
        }
    }
}

// MARK: - DC-2 RAM

/// RAM card: memory bar, used/total, pressure badge, swap line (DC-2).
struct RAMCard: View {
    let phase: DashboardCardPhase
    let ram: RAMSnapshot?

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.small) {
                cardTitle("dashboard.card.ram.title")
                switch phase {
                case .loading:
                    cardLoading()
                case .empty:
                    cardEmpty("memorychip")
                case .content:
                    if let ram {
                        HStack(alignment: .firstTextBaseline, spacing: AGSpacing.small) {
                            cardMono("\(formatBytes(ram.usedBytes)) / \(formatBytes(ram.totalBytes))")
                            Spacer()
                            AGStatusBadge(status: memoryPressureStatus(ram.pressure))
                        }
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

/// GPU card: gauge + line on Apple Silicon; AGEmptyState "unavailable" otherwise (DC-3).
struct GPUCard: View {
    let phase: DashboardCardPhase
    let gpu: GPUSnapshot?
    let history: [MetricSample]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.small) {
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
                    HStack(spacing: AGSpacing.medium) {
                        AGGauge(value: gpu?.utilization)
                        cardMono("\(Int((gpu?.utilization ?? 0).rounded()))%")
                    }
                    AGLineChart(samples: history)
                }
            }
        }
    }
}

// MARK: - DC-4 Network

/// Network card: dual-line chart, up/down rates, interface name (DC-4).
struct NetworkCard: View {
    let phase: DashboardCardPhase
    let network: NetworkSnapshot?
    let downHistory: [MetricSample]
    let upHistory: [MetricSample]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.small) {
                cardTitle("dashboard.card.network.title")
                switch phase {
                case .loading:
                    cardLoading()
                case .empty:
                    cardEmpty("arrow.up.arrow.down")
                case .content:
                    if let network {
                        cardCaption(L("dashboard.card.network.interface", network.interfaceName))
                        cardMono(networkRatesText(network))
                    }
                    AGNetworkChart(downSamples: downHistory, upSamples: upHistory)
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
                        AGGauge(value: battery.level)
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
