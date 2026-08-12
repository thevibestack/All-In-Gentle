import SwiftUI

struct ProjectsView: View {
    @State private var viewModel = ProjectsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                content
            }
            .navigationTitle("Projects")
            .task { await viewModel.load() }
        }
    }

    private var searchField: some View {
        TextField("Search projects", text: $viewModel.searchQuery)
            .textFieldStyle(.roundedBorder)
            .padding()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            Text(errorMessage)
                .foregroundStyle(.secondary)
                .padding()
        } else if viewModel.filteredItems.isEmpty {
            Text("No projects found")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            List(viewModel.filteredItems) { item in
                ProjectRow(item: item)
            }
        }
    }
}

private struct ProjectRow: View {
    let item: ProjectItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
            Text(item.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                ForEach(item.sources, id: \.self) { source in
                    Text(source.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}
