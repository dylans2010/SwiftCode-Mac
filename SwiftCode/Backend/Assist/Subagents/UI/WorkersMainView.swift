import SwiftUI

/// Dashboard view for all Assist Workers associated with the active task.
/// Supports status, progress, scope, result, errors, dependencies, cancellation, and reassignment.
@MainActor
public struct WorkersMainView: View {
    private var runtimeState = WorkerRuntimeState.shared
    @Environment(\.dismiss) private var dismiss

    @State private var filterMode: FilterMode = .all
    @State private var selectedWorkerForDetails: Worker? = nil
    @State private var workerToStop: Worker? = nil

    public enum FilterMode: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        case attention = "Needs Attention"

        public var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            metricsBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            filterBar
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

            Divider()

            ScrollView {
                if filteredWorkers.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredWorkers) { worker in
                            workerRow(worker)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 480, idealHeight: 600)
        .sheet(item: $selectedWorkerForDetails) { worker in
            WorkersInfoView(workerID: worker.id)
        }
        .sheet(item: $workerToStop) { worker in
            WorkerStopConfirmationSheet(worker: worker) {
                workerToStop = nil
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.sequence.fill")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("Assist Workers")
                    .font(.headline)
                Text("\(runtimeState.allWorkers.count) total · \(runtimeState.activeWorkers.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Metrics

    private var metricsBar: some View {
        HStack(spacing: 16) {
            metricItem(label: "Active", value: runtimeState.activeWorkers.count, color: .blue)
            metricItem(label: "Completed", value: runtimeState.completedWorkers.count, color: .green)
            metricItem(label: "Failed", value: runtimeState.failedWorkers.count, color: .red)
            metricItem(label: "Standby", value: runtimeState.standbyWorkers.count, color: .orange)
            Spacer()
        }
    }

    private func metricItem(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        HStack {
            Picker("Filter", selection: $filterMode) {
                ForEach(FilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer()

            Text("\(filteredWorkers.count) workers")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No workers match the selected filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Worker Row

    @ViewBuilder
    private func workerRow(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                detailContent(worker)
            }
            .padding(.top, 6)
        } label: {
            labelContent(worker)
        }
    }

    @ViewBuilder
    private func labelContent(_ worker: Worker) -> some View {
        HStack(spacing: 8) {
            Image(systemName: worker.status.sfSymbolName)
                .font(.caption)
                .foregroundStyle(statusColor(for: worker.status))
                .frame(width: 16)

            Text(worker.name)
                .font(.system(.subheadline, weight: .semibold))

            Text(worker.role)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(Int(worker.progressFraction * 100))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            if worker.status.isActive || worker.status == .standby {
                Button {
                    workerToStop = worker
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop this worker")
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ worker: Worker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Task")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(worker.task)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Scope")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(worker.scope)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(2)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Action")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(worker.currentAction.isEmpty ? "Idle" : worker.currentAction)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Phase")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(worker.currentPhase.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            ProgressView(value: worker.progressFraction)
                .tint(worker.status == .failed ? .red : .blue)

            HStack(spacing: 12) {
                Label("\(worker.fileChanges.count) files", systemImage: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label("+\(worker.totalLinesAdded) / -\(worker.totalLinesRemoved)", systemImage: "plusminus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label("\(worker.testsRun.count) tests", systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(worker.reviewState.rawValue)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(reviewColor(for: worker.reviewState))
            }

            if !worker.dependencies.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Depends on: \(worker.dependencies.count) worker(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = worker.errorState {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(error.message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            if let result = worker.result {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Build: \(result.buildResult) · Verification: \(result.verificationResult)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    selectedWorkerForDetails = worker
                } label: {
                    Label("Details", systemImage: "info.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                if worker.status.isActive || worker.status == .standby {
                    Button(role: .destructive) {
                        workerToStop = worker
                    } label: {
                        Label("Stop / Reassign", systemImage: "stop.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Spacer()
            }
        }
    }

    // MARK: - Filtering

    private var filteredWorkers: [Worker] {
        switch filterMode {
        case .all:
            return runtimeState.allWorkers
        case .active:
            return runtimeState.activeWorkers
        case .completed:
            return runtimeState.completedWorkers
        case .attention:
            return runtimeState.allWorkers.filter {
                $0.status == .failed || $0.status == .blocked || $0.status == .reassigning || $0.reviewState == .rejected || $0.reviewState == .repairRequired
            }
        }
    }

    // MARK: - Helpers

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

    private func reviewColor(for review: WorkerReviewState) -> Color {
        switch review {
        case .notReviewed: return .secondary
        case .reviewing: return .purple
        case .accepted: return .green
        case .rejected: return .red
        case .repairRequired: return .orange
        }
    }
}
