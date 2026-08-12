import SwiftUI

struct TokensView: View {
    @State private var viewModel = TokensViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Tokens")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        placeholderButton(title: "Export")
                    }
                }
                .task { await viewModel.load() }
        }
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
        } else if viewModel.items.isEmpty {
            Text("No token usage data")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            VStack(spacing: 0) {
                Table(viewModel.items) {
                    TableColumn("Project") { item in
                        Text(item.project)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Session") { item in
                        Text(item.session ?? "—")
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Prompt") { item in
                        Text("\(item.promptTokens)")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Completion") { item in
                        Text("\(item.completionTokens)")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Total") { item in
                        Text("\(item.totalTokens)")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Cost") { item in
                        Text(String(format: "%.4f", item.estimatedCost))
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Date") { item in
                        Text(item.timestamp, style: .date)
                            .monospacedDigit()
                    }
                    .width(min: 80, ideal: 120)
                }

                if viewModel.canLoadMore {
                    Button(action: { Task { await viewModel.loadNextPage() } }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Load More")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func placeholderButton(title: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Text(title)
                Text("Próximamente")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}
