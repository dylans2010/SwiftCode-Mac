import SwiftUI

/// Compact worker status list embedded within the primary Assist chat view.
/// Shows worker name, status, and a small SF Symbol. Not a card grid.
@MainActor
public struct WorkersOnAssistView: View {
    private var runtimeState = WorkerRuntimeState.shared

    @State private var selectedWorkerForDetails: Worker? = nil
    @State private var isMainDashboardPresented: Bool = false

    public init() {}

    public var body: some View {
        let workers = runtimeState.allWorkers
        if workers.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Workers")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    let activeCount = runtimeState.activeWorkers.count
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    Button {
                        isMainDashboardPresented = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Open full Workers dashboard")
                }
                .padding(.horizontal, 4)

                ForEach(workers) { worker in
                    Button {
                        selectedWorkerForDetails = worker
                    } label: {
                        compactRow(worker)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .sheet(item: $selectedWorkerForDetails) { worker in
                WorkersInfoView(workerID: worker.id)
            }
            .sheet(isPresented: $isMainDashboardPresented) {
                WorkersMainView()
            }
        }
    }

    @ViewBuilder
    private func compactRow(_ worker: Worker) -> some View {
        HStack(spacing: 6) {
            statusIcon(for: worker)
                .frame(width: 14)

            Text(worker.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(worker.status.rawValue)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor(for: worker.status))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusIcon(for worker: Worker) -> some View {
        switch worker.status {
        case .working:
            ProgressView()
                .scaleEffect(0.5)
                .tint(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed, .blocked:
            Image(systemName: "xmark.octagon.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .standby:
            Image(systemName: "pause.circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "slash.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .reviewing:
            Image(systemName: "eye.fill")
                .font(.caption2)
                .foregroundStyle(.purple)
        case .reassigning:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.yellow)
        default:
            Image(systemName: "hourglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(for status: WorkerStatus) -> Color {
        switch status {
        case .created, .queued, .starting, .cancelled: return .secondary
        case .assigned, .working: return .blue
        case .reviewing: return .purple
        case .completed: return .green
        case .standby, .reassigning: return .orange
        case .blocked, .failed: return .red
        }
    }
}
