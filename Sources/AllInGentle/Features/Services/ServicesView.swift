import SwiftUI

struct ServicesView: View {
    @State private var viewModel = ServicesViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("services.title"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: AGSpacing.xSmall) {
                            AGButton(
                                "services.safeRestart", systemImage: "arrow.clockwise", variant: .secondary, action: {}
                            )
                            .disabled(true)
                            AGStatusBadge(status: .placeholder)
                        }
                    }
                }
                .task { await viewModel.poll() }
                .onChange(of: appState.globalSearchQuery) { _, new in
                    viewModel.searchQuery = new
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.filteredStatuses.isEmpty {
            AGLoadingState(titleKey: "ds.state.loading")
        } else if let _ = viewModel.errorMessage, viewModel.filteredStatuses.isEmpty {
            AGErrorState(
                titleKey: "services.error.title",
                messageKey: "services.error.message",
                retry: { Task { await viewModel.poll() } }
            )
        } else if viewModel.filteredStatuses.isEmpty {
            AGEmptyState(
                systemImage: "checkmark.shield",
                titleKey: "services.empty",
                messageKey: "services.empty.message"
            )
        } else {
            List(viewModel.filteredStatuses) { status in
                AGListRow {
                    ServiceRow(status: status)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: AGSpacing.medium, bottom: 0, trailing: AGSpacing.medium))
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ServiceRow: View {
    let status: ServiceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.xSmall) {
            HStack(spacing: AGSpacing.small) {
                Text(status.name)
                    .font(AGTypography.headline)
                    .foregroundStyle(AGColors.textPrimary)
                Spacer()
                AGStatusBadge(status: status.isRunning ? .live : .disabled)
            }

            HStack(spacing: AGSpacing.large) {
                if let pid = status.pid {
                    LabeledValue(label: L("services.pid"), value: String(pid))
                }
                if let port = status.port {
                    LabeledValue(label: L("services.port"), value: String(port))
                }
                if let uptime = status.uptime {
                    LabeledValue(label: L("services.uptime"), value: formatUptime(uptime))
                }
            }

            if let error = status.lastError {
                Text(error)
                    .font(AGTypography.caption)
                    .foregroundStyle(AGColors.statusError)
                    .lineLimit(2)
            }
        }
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
            Text(label)
                .font(AGTypography.caption)
                .foregroundStyle(AGColors.textSecondary)
            Text(value)
                .font(AGTypography.body)
                .foregroundStyle(AGColors.textPrimary)
        }
    }
}

private func formatUptime(_ interval: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: interval) ?? "\(Int(interval))s"
}
