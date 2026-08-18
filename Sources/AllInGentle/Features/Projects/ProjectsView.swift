import SwiftUI

struct ProjectsView: View {
    @State private var viewModel = ProjectsViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                sidebarContent
            }
        } detail: {
            detailContent
        }
        .navigationTitle(L("projects.title"))
        .task {
            viewModel.onSelectionChange = { appState.selectedProjectPath = $0 }
            await viewModel.load(initialSelectedPath: appState.selectedProjectPath)
        }
    }

    private var searchField: some View {
        AGSearchField(
            text: $viewModel.searchQuery,
            isFocused: Bindable(appState).searchFocused,
            placeholderKey: "projects.search"
        )
        .padding(AGSpacing.medium)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            AGLoadingState(titleKey: "ds.state.loading")
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            AGErrorState(
                message: errorMessage,
                retry: { Task { await viewModel.load() } }
            )
        } else if viewModel.filteredItems.isEmpty {
            AGEmptyState(
                systemImage: "folder",
                titleKey: "projects.empty",
                messageKey: "projects.empty.message"
            )
        } else {
            List(selection: $viewModel.selection) {
                ForEach(viewModel.filteredItems) { item in
                    AGListRow {
                        ProjectRow(item: item)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: AGSpacing.medium, bottom: 0, trailing: AGSpacing.medium))
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selected = viewModel.selection {
            ProjectDetailView(project: selected)
        } else {
            AGEmptyState(
                systemImage: "folder",
                titleKey: "projectDetail.empty.title",
                messageKey: "projectDetail.empty.message"
            )
        }
    }
}

private struct ProjectRow: View {
    let item: ProjectItem

    var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.xSmall) {
            Text(item.name)
                .font(AGTypography.headline)
                .foregroundStyle(AGColors.textPrimary)
            Text(item.path)
                .font(AGTypography.caption)
                .foregroundStyle(AGColors.textSecondary)
                .lineLimit(1)
            HStack(spacing: AGSpacing.xSmall) {
                ForEach(item.sources, id: \.self) { source in
                    SourceBadge(source: source)
                }
            }
        }
    }
}

struct SourceBadge: View {
    let source: Project.Source

    var body: some View {
        Text(source.rawValue)
            .font(AGTypography.caption)
            .foregroundStyle(AGColors.textSecondary)
            .padding(.horizontal, AGSpacing.badgePaddingHorizontal)
            .padding(.vertical, AGSpacing.badgePaddingVertical)
            .background(AGColors.surfaceSecondary)
            .clipShape(Capsule())
    }
}
