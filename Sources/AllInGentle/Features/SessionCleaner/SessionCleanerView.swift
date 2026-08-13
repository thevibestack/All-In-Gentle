import SwiftUI

struct SessionCleanerView: View {
    @State private var viewModel = SessionCleanerViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("sessionCleaner.title"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: AGSpacing.xSmall) {
                            AGButton("sessionCleaner.cleanUp", systemImage: "trash", variant: .danger, action: {})
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
        if viewModel.isLoading && viewModel.filteredGroups.isEmpty {
            AGLoadingState(titleKey: "ds.state.loading")
        } else if let errorMessage = viewModel.errorMessage, viewModel.filteredGroups.isEmpty {
            AGErrorState(
                message: errorMessage,
                retry: { Task { await viewModel.load() } }
            )
        } else if viewModel.filteredGroups.isEmpty {
            AGEmptyState(
                systemImage: "trash",
                titleKey: "sessionCleaner.empty",
                messageKey: "sessionCleaner.empty.message"
            )
        } else {
            List(viewModel.filteredGroups) { group in
                AGListRow {
                    SessionGroupRow(group: group)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: AGSpacing.medium, bottom: 0, trailing: AGSpacing.medium))
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct SessionGroupRow: View {
    let group: SessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.xSmall) {
            HStack(spacing: AGSpacing.small) {
                Text(group.name)
                    .font(AGTypography.headline)
                    .foregroundStyle(AGColors.textPrimary)
                Spacer()
                Text(L("sessionCleaner.sessions.count", group.sessions.count))
                    .font(AGTypography.caption)
                    .foregroundStyle(AGColors.textSecondary)
            }

            HStack(spacing: AGSpacing.large) {
                LabeledValue(label: L("sessionCleaner.tokens"), value: "\(group.totalTokens)")
                LabeledValue(label: L("sessionCleaner.cost"), value: String(format: "%.4f", group.totalCost))
                LabeledValue(label: L("sessionCleaner.latest"), value: group.latestDate.formatted(date: .abbreviated, time: .omitted))
            }

            if !group.sessions.isEmpty {
                DisclosureGroup(L("sessionCleaner.sessions")) {
                    ForEach(group.sessions) { session in
                        HStack(spacing: AGSpacing.small) {
                            Text(session.sessionName)
                                .font(AGTypography.caption)
                                .foregroundStyle(AGColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(session.totalTokens)")
                                .font(AGTypography.monoCaption)
                                .foregroundStyle(AGColors.textSecondary)
                                .monospacedDigit()
                            Text(String(format: "%.4f", session.estimatedCost))
                                .font(AGTypography.monoCaption)
                                .foregroundStyle(AGColors.textSecondary)
                                .monospacedDigit()
                            Text(session.latestDate, style: .date)
                                .font(AGTypography.monoCaption)
                                .foregroundStyle(AGColors.textSecondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, AGSpacing.xxSmall)
                    }
                }
                .font(AGTypography.caption)
                .foregroundStyle(AGColors.textSecondary)
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
                .monospacedDigit()
        }
    }
}
