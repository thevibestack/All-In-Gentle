import SwiftUI

struct WikiView: View {
    @State private var viewModel = WikiViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationTitle(L("wiki.title"))
        .task { await viewModel.loadDocuments() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            memoriesList
            Divider()
            documentsList
        }
    }

    private var searchField: some View {
        TextField(L("wiki.search"), text: $viewModel.searchQuery)
            .textFieldStyle(.roundedBorder)
            .padding()
    }

    private var memoriesList: some View {
        List(viewModel.results) { observation in
            VStack(alignment: .leading, spacing: 4) {
                Text(observation.title)
                    .font(.headline)
                if let project = observation.project {
                    Text(project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var documentsList: some View {
        List(viewModel.documents, selection: $viewModel.selectedDocument) { document in
            Text(document.title ?? document.path)
                .lineLimit(1)
        }
        .onChange(of: viewModel.selectedDocument) { _, document in
            if let document {
                viewModel.selectDocument(document)
            }
        }
    }

    private var detailPane: some View {
        ScrollView {
            if viewModel.previewText.isEmpty {
                Text(L("wiki.preview"))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                Text(viewModel.previewText)
                    .font(.system(size: 14, design: .monospaced))
                    .padding()
            }
        }
    }
}
