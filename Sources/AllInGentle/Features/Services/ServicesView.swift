import SwiftUI

struct ServicesView: View {
    @State private var viewModel = ServicesViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Services")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        placeholderButton(title: "Safe Restart")
                    }
                }
                .task { await viewModel.poll() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.statuses.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.statuses.isEmpty {
            Text(errorMessage)
                .foregroundStyle(.secondary)
                .padding()
        } else if viewModel.statuses.isEmpty {
            Text("No services configured")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            List(viewModel.statuses) { status in
                ServiceRow(status: status)
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

private struct ServiceRow: View {
    let status: ServiceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status.name)
                    .font(.headline)
                Spacer()
                StatusIndicator(isRunning: status.isRunning)
            }

            HStack(spacing: 16) {
                if let pid = status.pid {
                    LabeledValue(label: "PID", value: String(pid))
                }
                if let port = status.port {
                    LabeledValue(label: "Port", value: String(port))
                }
                if let uptime = status.uptime {
                    LabeledValue(label: "Uptime", value: formatUptime(uptime))
                }
            }

            if let error = status.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatusIndicator: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(isRunning ? "Running" : "Stopped")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

private func formatUptime(_ interval: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: interval) ?? "\(Int(interval))s"
}
