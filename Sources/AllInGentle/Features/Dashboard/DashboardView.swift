import SwiftUI

/// Adaptive grid columns for the dashboard (spec DS-3): at least two columns
/// in a 600pt window, no card below the 280pt minimum.
func dashboardGridColumns() -> [GridItem] {
    [GridItem(.adaptive(minimum: 280), spacing: AGSpacing.gridGapDense)]
}

/// Home dashboard shell (DS-2/DS-3): NavigationStack → ScrollView →
/// adaptive LazyVGrid of the six metric cards.
struct DashboardView: View {
    let viewModel: DashboardViewModel

    init(viewModel: DashboardViewModel = DashboardViewModel()) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DashboardGrid(viewModel: viewModel)
                    .padding(AGSpacing.medium)
            }
            .navigationTitle(L("dashboard.title"))
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
        }
    }
}

/// The six-card grid (DS-3). Extracted from the navigation shell so the card
/// degradation paths can be rendered headlessly in tests (DC-7/G-5). The
/// battery card is included only while a battery exists (DC-5).
struct DashboardGrid: View {
    let viewModel: DashboardViewModel

    var body: some View {
        LazyVGrid(columns: dashboardGridColumns(), alignment: .leading, spacing: AGSpacing.gridGapDense) {
            CPUCard(phase: viewModel.cardPhase(viewModel.cpu), cpu: viewModel.cpu, history: viewModel.cpuHistory)
            RAMCard(phase: viewModel.cardPhase(viewModel.ram), ram: viewModel.ram)
            GPUCard(phase: viewModel.cardPhase(viewModel.gpu), gpu: viewModel.gpu, history: viewModel.gpuHistory)
            NetworkCard(
                phase: viewModel.cardPhase(viewModel.network),
                network: viewModel.network,
                downHistory: viewModel.networkDownHistory,
                upHistory: viewModel.networkUpHistory
            )
            if batteryCardVisible(viewModel.battery) {
                BatteryCard(battery: viewModel.battery)
            }
            ServicesCard(statuses: viewModel.serviceStatuses)
        }
    }
}
