import SwiftUI

struct ProjectDetailView: View {
    let project: ProjectItem
    @State private var viewModel = ProjectDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGSpacing.large) {
                VStack(alignment: .leading, spacing: AGSpacing.small) {
                    Text(project.name)
                        .font(AGTypography.title)
                        .foregroundStyle(AGColors.textPrimary)
                    Text(project.path)
                        .font(AGTypography.caption)
                        .foregroundStyle(AGColors.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: AGSpacing.xSmall) {
                        ForEach(project.sources, id: \.self) { source in
                            SourceBadge(source: source)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AGSpacing.small) {
                    HStack(spacing: AGSpacing.xSmall) {
                        Text(L("projectDetail.memories.title"))
                            .font(AGTypography.headline)
                            .foregroundStyle(AGColors.textPrimary)
                        if viewModel.usedFallbackSearch {
                            Text(L("projectDetail.memories.fallback"))
                                .font(AGTypography.caption)
                                .foregroundStyle(AGColors.statusPlaceholder)
                        }
                    }

                    if viewModel.memories.isEmpty {
                        Text(L("projectDetail.memories.empty"))
                            .font(AGTypography.body)
                            .foregroundStyle(AGColors.textSecondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: AGSpacing.small) {
                            ForEach(viewModel.memories) { memory in
                                AGCard {
                                    VStack(alignment: .leading, spacing: AGSpacing.xSmall) {
                                        Text(memory.title)
                                            .font(AGTypography.headline)
                                            .foregroundStyle(AGColors.textPrimary)
                                        Text(memory.content)
                                            .font(AGTypography.body)
                                            .foregroundStyle(AGColors.textSecondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AGSpacing.small) {
                    Text(L("projectDetail.documents.title"))
                        .font(AGTypography.headline)
                        .foregroundStyle(AGColors.textPrimary)

                    if viewModel.documents.isEmpty {
                        Text(L("projectDetail.documents.empty"))
                            .font(AGTypography.body)
                            .foregroundStyle(AGColors.textSecondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: AGSpacing.small) {
                            ForEach(viewModel.documents) { document in
                                AGCard {
                                    VStack(alignment: .leading, spacing: AGSpacing.xSmall) {
                                        Text(document.title ?? (document.path as NSString).lastPathComponent)
                                            .font(AGTypography.headline)
                                            .foregroundStyle(AGColors.textPrimary)
                                        Text(document.path)
                                            .font(AGTypography.caption)
                                            .foregroundStyle(AGColors.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(AGSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: project.path) {
            viewModel.load(projectPath: project.path)
        }
    }
}
