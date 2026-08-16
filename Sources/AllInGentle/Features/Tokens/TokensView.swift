import SwiftUI

struct TokensView: View {
    @State private var viewModel = TokensViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("tokens.title"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: AGSpacing.xSmall) {
                            AGButton(
                                "tokens.export", systemImage: "square.and.arrow.up", variant: .secondary, action: {}
                            )
                            .disabled(true)
                            AGStatusBadge(status: .placeholder)
                        }
                    }
                }
                .task { await viewModel.load() }
                .onChange(of: appState.globalSearchQuery) { _, new in
                    viewModel.searchQuery = new
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.filteredItems.isEmpty {
            AGLoadingState(titleKey: "ds.state.loading")
        } else if let errorMessage = viewModel.errorMessage, viewModel.filteredItems.isEmpty {
            AGErrorState(
                message: errorMessage,
                retry: { Task { await viewModel.load() } }
            )
        } else if viewModel.filteredItems.isEmpty {
            AGEmptyState(
                systemImage: "chart.bar",
                titleKey: "tokens.empty",
                messageKey: "tokens.empty.message"
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Table(viewModel.filteredItems) {
                    TableColumn(L("tokens.column.project")) { item in
                        Text(item.project)
                            .font(AGTypography.body)
                            .foregroundStyle(AGColors.textPrimary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn(L("tokens.column.session")) { item in
                        Text(item.session ?? "—")
                            .font(AGTypography.body)
                            .foregroundStyle(AGColors.textPrimary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn(L("tokens.column.prompt")) { item in
                        Text("\(item.promptTokens)")
                            .font(AGTypography.monoCaption)
                            .foregroundStyle(AGColors.textPrimary)
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn(L("tokens.column.completion")) { item in
                        Text("\(item.completionTokens)")
                            .font(AGTypography.monoCaption)
                            .foregroundStyle(AGColors.textPrimary)
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn(L("tokens.column.total")) { item in
                        Text("\(item.totalTokens)")
                            .font(AGTypography.monoCaption)
                            .foregroundStyle(AGColors.textPrimary)
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn(L("tokens.column.cost")) { item in
                        Text(String(format: "%.4f", item.estimatedCost))
                            .font(AGTypography.monoCaption)
                            .foregroundStyle(AGColors.textPrimary)
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn(L("tokens.column.date")) { item in
                        Text(item.timestamp, style: .date)
                            .font(AGTypography.monoCaption)
                            .foregroundStyle(AGColors.textSecondary)
                            .monospacedDigit()
                    }
                    .width(min: 80, ideal: 120)
                }

                if viewModel.canLoadMore {
                    AGButton("tokens.loadMore", systemImage: "arrow.down", variant: .secondary) {
                        Task { await viewModel.loadNextPage() }
                    }
                    .disabled(viewModel.isLoading)
                    .frame(maxWidth: .infinity, minHeight: AGSpacing.rowHeightLarge)
                    .padding(AGSpacing.medium)
                }
            }
        }
    }
}
