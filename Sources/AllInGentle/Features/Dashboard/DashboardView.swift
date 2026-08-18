import SwiftUI

/// Adaptive grid columns for the dashboard (spec DS-3): at least two columns
/// in a 600pt window, no card below the 280pt minimum.
func dashboardGridColumns() -> [GridItem] {
    [GridItem(.adaptive(minimum: 280), spacing: AGSpacing.medium)]
}

/// Home dashboard shell (DS-2/DS-3): NavigationStack → ScrollView →
/// adaptive LazyVGrid of DashboardCards. Card bodies are minimal live
/// summaries; full widget compositions land with the cards phase (PR 6).
struct DashboardView: View {
    let viewModel: DashboardViewModel

    init(viewModel: DashboardViewModel = DashboardViewModel()) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: dashboardGridColumns(), alignment: .leading, spacing: AGSpacing.medium) {
                    metricCard(
                        "dashboard.card.cpu.title", viewModel.cardPhase(viewModel.cpu),
                        viewModel.cpu.map { "\(Int($0.total.rounded()))%" })
                    metricCard(
                        "dashboard.card.ram.title", viewModel.cardPhase(viewModel.ram),
                        viewModel.ram.map { "\(formatBytes($0.usedBytes)) / \(formatBytes($0.totalBytes))" })
                    metricCard(
                        "dashboard.card.gpu.title", viewModel.cardPhase(viewModel.gpu),
                        viewModel.gpu.map { "\(Int($0.utilization.rounded()))%" })
                    metricCard(
                        "dashboard.card.network.title", viewModel.cardPhase(viewModel.network),
                        viewModel.network.map {
                            "↓ \(formatRate($0.receivedBytesPerSec))  ↑ \(formatRate($0.sentBytesPerSec))"
                        })
                    metricCard(
                        "dashboard.card.battery.title", viewModel.cardPhase(viewModel.battery),
                        viewModel.battery.map { "\(Int($0.level.rounded()))%" })
                    metricCard(
                        "dashboard.card.services.title",
                        viewModel.serviceStatuses.isEmpty ? .loading : .content,
                        L("dashboard.services.running", viewModel.runningServiceCount, viewModel.serviceTotal))
                }
                .padding(AGSpacing.medium)
            }
            .navigationTitle(L("dashboard.title"))
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
        }
    }

    /// Minimal placeholder card: localized title + primary value; spinner
    /// before the first batch, empty state while a metric is unavailable.
    private func metricCard(_ titleKey: String, _ phase: DashboardCardPhase, _ value: String?) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AGSpacing.xSmall) {
                Text(L(titleKey))
                    .font(AGTypography.headline)
                    .foregroundStyle(AGColors.textPrimary)
                switch phase {
                case .loading:
                    ProgressView().controlSize(.small)
                case .empty:
                    Text(L("dashboard.card.empty"))
                        .font(AGTypography.body)
                        .foregroundStyle(AGColors.textSecondary)
                case .content:
                    Text(value ?? "")
                        .font(AGTypography.mono)
                        .foregroundStyle(AGColors.textPrimary)
                        .lineLimit(1)
                }
            }
        }
    }
}
