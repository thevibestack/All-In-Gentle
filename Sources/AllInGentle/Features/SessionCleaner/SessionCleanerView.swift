import SwiftUI

struct SessionCleanerView: View {
    @State private var viewModel = SessionCleanerViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("sessionCleaner.title"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        placeholderButton(title: L("sessionCleaner.cleanUp"))
                    }
                }
                .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.groups.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.groups.isEmpty {
            Text(errorMessage)
                .foregroundStyle(.secondary)
                .padding()
        } else if viewModel.groups.isEmpty {
            Text(L("sessionCleaner.empty"))
                .foregroundStyle(.secondary)
                .padding()
        } else {
            List(viewModel.groups) { group in
                SessionGroupRow(group: group)
            }
        }
    }

    private func placeholderButton(title: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Text(title)
                InteractionStateBadge(state: .placeholder)
            }
        }
    }
}

private struct SessionGroupRow: View {
    let group: SessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.name)
                    .font(.headline)
                Spacer()
                Text(L("sessionCleaner.sessions.count", group.sessions.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                LabeledValue(label: L("sessionCleaner.tokens"), value: "\(group.totalTokens)")
                LabeledValue(label: L("sessionCleaner.cost"), value: String(format: "%.4f", group.totalCost))
                LabeledValue(label: L("sessionCleaner.latest"), value: group.latestDate.formatted(date: .abbreviated, time: .omitted))
            }

            if !group.sessions.isEmpty {
                DisclosureGroup(L("sessionCleaner.sessions")) {
                    ForEach(group.sessions) { session in
                        HStack(spacing: 8) {
                            Text(session.sessionName)
                                .lineLimit(1)
                            Spacer()
                            Text("\(session.totalTokens)")
                                .monospacedDigit()
                            Text(String(format: "%.4f", session.estimatedCost))
                                .monospacedDigit()
                            Text(session.latestDate, style: .date)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .padding(.vertical, 2)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }
}
