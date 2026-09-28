import SwiftUI

/// Detailed inspection view for a single Assist Worker.
/// Strictly non-conversational — the only interactive control is "Stop Worker".
@MainActor
public struct WorkersInfoView: View {
    let workerID: UUID

    private var runtimeState = WorkerRuntimeState.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingStopSheet = false

    public init(workerID: UUID) {
        self.workerID = workerID
    }

    public var body: some View {
        if let worker = runtimeState.getWorker(id: workerID) {
            VStack(spacing: 0) {
                headerView(for: worker)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        statusSection(worker)
                        activitySection(worker)
                        scopeSection(worker)
                        filesSection(worker)
                        testsSection(worker)
                        verificationSection(worker)
                        if worker.errorState != nil {
                            errorSection(worker)
                        }
                        if worker.handoffState != nil {
                            handoffSection(worker)
                        }
                        if !worker.dependencies.isEmpty {
                            dependenciesSection(worker)
                        }
                        timestampsSection(worker)
                    }
                    .padding(16)
                }
            }
            .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 600)
            .sheet(isPresented: $showingStopSheet) {
                WorkerStopConfirmationSheet(worker: worker) {
                    showingStopSheet = false
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Worker not found or already removed")
                    .font(.headline)
                Button("Close") { dismiss() }
            }
            .frame(width: 400, height: 250)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerView(for worker: Worker) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: worker.status.sfSymbolName)
                .font(.title3)
                .foregroundStyle(statusColor(for: worker.status))

            VStack(alignment: .leading, spacing: 2) {
                Text(worker.name)
                    .font(.headline)
                Text(worker.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if worker.status.isActive || worker.status == .standby {
                Button(role: .destructive) {
                    showingStopSheet = true
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Halt this worker and either preserve work or reassign remaining scope")
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    @ViewBuilder
    private func statusSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Status")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(worker.status.rawValue)
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(statusColor(for: worker.status))
                }
                HStack {
                    Text("Phase")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(worker.currentPhase.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Review")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(worker.reviewState.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(reviewColor(for: worker.reviewState))
                }
                if !worker.modelUsed.isEmpty {
                    HStack {
                        Text("Model")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(worker.modelUsed)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if !worker.skillsUsed.isEmpty {
                    HStack(alignment: .top) {
                        Text("Skills")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(worker.skillsUsed.joined(separator: ", "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Status", systemImage: "info.circle")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func activitySection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(worker.currentAction.isEmpty ? "Idle" : worker.currentAction)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)

                ProgressView(value: worker.progressFraction)
                    .tint(worker.status == .failed ? .red : .blue)

                HStack {
                    Text("\(Int(worker.progressFraction * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let lastCompleted = worker.progress.lastCompleted {
                        Text("Last: \(lastCompleted)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let nextPlan = worker.progress.nextPlan {
                    Text("Next: \(nextPlan)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Current Activity", systemImage: "bolt.fill")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func scopeSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("Task")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(worker.task)
                    .font(.system(.caption, design: .default))

                Divider().padding(.vertical, 2)

                Text("Scope")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(worker.scope)
                    .font(.system(.caption, design: .monospaced))
            }
            .padding(.top, 4)
        } label: {
            Label("Assignment", systemImage: "scope")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func filesSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                if worker.fileChanges.isEmpty {
                    Text("No files modified yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(worker.fileChanges) { change in
                        HStack(spacing: 6) {
                            Image(systemName: change.changeType.sfSymbolName)
                                .font(.caption2)
                                .foregroundStyle(fileColor(for: change.changeType))
                            Text(change.path)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Text("+\(change.linesAdded) / -\(change.linesRemoved)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Files (\(worker.fileChanges.count))", systemImage: "doc.badge.gearshape")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func testsSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                if worker.testsRun.isEmpty {
                    Text("No tests executed yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(worker.testsRun) { test in
                        HStack(spacing: 6) {
                            Image(systemName: test.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(test.passed ? .green : .red)
                            Text(test.testName)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.2fs", test.duration))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Tests (\(worker.testsRun.count))", systemImage: "checkmark.seal")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func verificationSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Verification State")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(worker.verificationState)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let result = worker.result {
                    Divider().padding(.vertical, 2)
                    Text("Build: \(result.buildResult)")
                        .font(.system(size: 10, design: .monospaced))
                    Text("Verification: \(result.verificationResult)")
                        .font(.system(size: 10, design: .monospaced))
                    Text("Duration: \(Int(result.executionDuration))s")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !result.knownIssues.isEmpty {
                        Text("Known Issues: \(result.knownIssues.joined(separator: ", "))")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Verification", systemImage: "checkmark.shield")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func errorSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                if let error = worker.errorState {
                    Text(error.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                    if let details = error.details {
                        Text(details)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if error.recoverable {
                        Text("Recoverable")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func handoffSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                if let handoff = worker.handoffState {
                    Text("Reason: \(handoff.reason)")
                        .font(.caption)
                    Text("Mode: \(handoff.mode.rawValue)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !handoff.completedWork.isEmpty {
                        Text("Completed: \(handoff.completedWork.count) items")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if let replacementID = handoff.replacementWorkerID {
                        Text("Replacement: \(replacementID.uuidString.prefix(8))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                } else if let cancellation = worker.cancellationReason {
                    Text("Cancelled: \(cancellation)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Handoff", systemImage: "arrow.triangle.branch")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func dependenciesSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(worker.dependencies, id: \.self) { depID in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let depWorker = runtimeState.getWorker(id: depID) {
                            Text(depWorker.name)
                                .font(.system(size: 10, design: .monospaced))
                            Spacer()
                            Text(depWorker.status.rawValue)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(statusColor(for: depWorker.status))
                        } else {
                            Text(depID.uuidString.prefix(8))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Dependencies (\(worker.dependencies.count))", systemImage: "arrow.triangle.branch")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func timestampsSection(_ worker: Worker) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                timestampRow("Created", worker.createdAt)
                if let started = worker.startedAt {
                    timestampRow("Started", started)
                }
                if let completed = worker.completedAt {
                    timestampRow("Completed", completed)
                }
                timestampRow("Updated", worker.updatedAt)
            }
            .padding(.top, 4)
        } label: {
            Label("Timestamps", systemImage: "clock")
                .font(.subheadline.bold())
        }
    }

    private func timestampRow(_ label: String, _ date: Date) -> some View {
        HStack {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Text(date, style: .time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
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

    private func fileColor(for type: FileChangeType) -> Color {
        switch type {
        case .created: return .green
        case .modified: return .blue
        case .deleted: return .red
        case .renamed: return .orange
        }
    }
}
