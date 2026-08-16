import SwiftUI

struct WikiView: View {
    @State private var viewModel = WikiViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationTitle(L("wiki.title"))
        .task {
            viewModel.selectedProjectPath = appState.selectedProjectPath
            viewModel.loadDocuments(forProjectPath: appState.selectedProjectPath)
        }
        .onChange(of: appState.selectedProjectPath) { _, new in
            viewModel.selectedProjectPath = new
            viewModel.loadDocuments(forProjectPath: new)
        }
        .onChange(of: appState.globalSearchQuery) { _, new in
            viewModel.searchQuery = new
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            AGSearchField(text: $viewModel.searchQuery, placeholderKey: "wiki.search")
                .padding(AGSpacing.medium)

            if appState.selectedProjectPath == nil {
                AGEmptyState(
                    systemImage: "folder.badge.questionmark",
                    titleKey: "wiki.noProject.title",
                    messageKey: "wiki.noProject.message"
                )
            } else if viewModel.isLoadingDocuments && viewModel.documents.isEmpty && viewModel.results.isEmpty {
                AGLoadingState(titleKey: "wiki.loading")
            } else if viewModel.documents.isEmpty && viewModel.results.isEmpty {
                if let _ = viewModel.errorMessage {
                    AGErrorState(
                        message: viewModel.errorMessage ?? L("ds.state.error.message"),
                        retry: { viewModel.loadDocuments() }
                    )
                } else {
                    AGEmptyState(
                        systemImage: "books.vertical",
                        titleKey: "wiki.noData.title",
                        messageKey: "wiki.noData.message"
                    )
                }
            } else {
                memoriesList
                Divider()
                documentsList
            }
        }
    }

    private var memoriesList: some View {
        List(viewModel.results) { observation in
            AGListRow {
                VStack(alignment: .leading, spacing: AGSpacing.xxSmall) {
                    Text(observation.title)
                        .font(AGTypography.headline)
                        .foregroundStyle(AGColors.textPrimary)
                    if let project = observation.project {
                        Text(project)
                            .font(AGTypography.caption)
                            .foregroundStyle(AGColors.textSecondary)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: AGSpacing.medium, bottom: 0, trailing: AGSpacing.medium))
        }
        .scrollContentBackground(.hidden)
        .frame(minHeight: 120)
    }

    private var documentsList: some View {
        List(viewModel.documents, selection: $viewModel.selectedDocument) { document in
            AGListRow {
                Text(document.title ?? document.path)
                    .font(AGTypography.body)
                    .foregroundStyle(AGColors.textPrimary)
                    .lineLimit(1)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: AGSpacing.medium, bottom: 0, trailing: AGSpacing.medium))
        }
        .scrollContentBackground(.hidden)
        .onChange(of: viewModel.selectedDocument) { _, document in
            if let document {
                viewModel.selectDocument(document)
            }
        }
    }

    private var detailPane: some View {
        ScrollView {
            if let selectedDocument = viewModel.selectedDocument {
                if viewModel.previewText.isEmpty && viewModel.errorMessage != nil {
                    AGErrorState(
                        message: viewModel.errorMessage ?? L("ds.state.error.message"),
                        retry: { viewModel.selectDocument(selectedDocument) }
                    )
                } else if viewModel.previewText.isEmpty {
                    AGLoadingState(titleKey: "ds.state.loading")
                } else {
                    AGCard {
                        MarkdownText(viewModel.previewText)
                    }
                    .padding(AGSpacing.medium)
                }
            } else {
                AGEmptyState(
                    systemImage: "doc.text",
                    titleKey: "wiki.empty.title",
                    messageKey: "wiki.empty.message"
                )
            }
        }
    }
}
