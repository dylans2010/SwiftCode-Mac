import SwiftUI

/// Detailed inspection view for a single Assist Worker.
/// Displays authoritative real-time diagnostics, assignment boundaries, real file mutations,
/// event timelines, and review status.
///
/// Invariant: Strictly non-conversational. The only interactive control is "Stop Worker".
@MainActor
public struct WorkersInfoView: View {
    let workerID: UUID
    
    private var runtimeState = WorkerRuntimeState.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingStopSheet: Bool = false
    @State private var selectedTab: InfoTab = .overview
    
    public enum InfoTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case files = "Files & Changes"
        case validation = "Tests & Verification"
        case timeline = "Event Timeline"
        case history = "Lineage & Handoff"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .overview: return "info.circle"
            case .files: return "doc.badge.gearshape"
            case .validation: return "checkmark.seal"
            case .timeline: return "clock.arrow.circlepath"
            case .history: return "arrow.triangle.branch"
            }
        }
    }
    
    public init(workerID: UUID) {
        self.workerID = workerID
    }
    
    public var body: some View {
        if let worker = runtimeState.getWorker(id: workerID) {
            VStack(spacing: 0) {
                // Header Bar
                headerView(for: worker)
                
                Divider()
                
                // Segmented Picker
                Picker("Section", selection: $selectedTab) {
                    ForEach(InfoTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider()
                
                // Tab Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .overview:
                            overviewSection(worker)
                        case .files:
                            filesSection(worker)
                        case .validation:
                            validationSection(worker)
                        case .timeline:
                            timelineSection(worker)
                        case .history:
                            historySection(worker)
                        }
                    }
                    .padding(16)
                }
            }
            .frame(minWidth: 580, idealWidth: 680, minHeight: 480, idealHeight: 560)
            .sheet(isPresented: $showingStopSheet) {
                WorkerStopConfirmationSheet(worker: worker) {
                    showingStopSheet = false
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Worker not found or already removed")
                    .font(.headline)
                Button("Close") {
                    dismiss()
                }
            }
            .frame(width: 400, height: 250)
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private func headerView(for worker: Worker) -> some View {
        HStack(alignment: .center, spacing: 12) {
            statusBadgeLarge(for: worker.status)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worker.name)
                        .font(.title3.bold())
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(worker.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text("ID: \(worker.id.uuidString.prefix(8)) • Task: \(worker.parentTaskID.uuidString.prefix(8))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Only action permitted per Canonical Invariants: Stop Worker
            if worker.status.isActive || worker.status == .standby {
                Button(role: .destructive) {
                    showingStopSheet = true
                } label: {
                    Label("Stop Worker", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Halt this worker and either preserve work or reassign remaining scope")
            }
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Overview Section
    
    @ViewBuilder
    private func overviewSection(_ worker: Worker) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Current Activity Card
            GroupBox(label: Label("Current Activity", systemImage: "bolt.fill")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(worker.currentAction.isEmpty ? "Idle" : worker.currentAction)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(worker.currentPhase.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    
                    ProgressView(value: worker.progressFraction)
                        .tint(.blue)
                    
                    Text("Progress: \(Int(worker.progressFraction * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }
            
            // Assignment Scope Card
            GroupBox(label: Label("Assignment Boundaries", systemImage: "scope")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Task Objective:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(worker.task)
                        .font(.system(.subheadline, design: .default))
                    
                    Divider().padding(.vertical, 2)
                    
                    Text("Designated Scope (Exclusions Enforced):")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(worker.scope)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(6)
            }
            
            // Continuous Recap Card
            if !worker.recap.isEmpty {
                GroupBox(label: Label("Continuous Narrative Recap", systemImage: "text.alignleft")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(worker.recap, id: \.self) { point in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(.blue)
                                Text(point)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(6)
                }
            }
            
            // Review State Card
            GroupBox(label: Label("Parent Review Status", systemImage: "checkmark.shield")) {
                HStack(spacing: 12) {
                    Text("Status:")
                        .font(.caption.bold())
                    Text(worker.reviewState.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(reviewColor(for: worker.reviewState).opacity(0.15), in: Capsule())
                        .foregroundStyle(reviewColor(for: worker.reviewState))
                    
                    Spacer()
                    
                    if let result = worker.result {
                        Text("Completed in \(Int(result.executionDuration))s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }
        }
    }
    
    // MARK: - Files Section
    
    @ViewBuilder
    private func filesSection(_ worker: Worker) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File Changes (\(worker.fileChanges.count))")
                    .font(.headline)
                Spacer()
                Text("+\(worker.totalLinesAdded) / -\(worker.totalLinesRemoved)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }
            
            if worker.fileChanges.isEmpty {
                Text("No files modified yet by this Worker.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(worker.fileChanges) { change in
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(for: change.changeType))
                            .foregroundStyle(fileColor(for: change.changeType))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.path)
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                            Text(change.changeType.rawValue.capitalized)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Text("+\(change.linesAdded)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.green)
                            Text("-\(change.linesRemoved)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
    
    // MARK: - Validation Section
    
    @ViewBuilder
    private func validationSection(_ worker: Worker) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automated Test Runs (\(worker.testsRun.count))")
                .font(.headline)
            
            if worker.testsRun.isEmpty {
                Text("No tests executed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(worker.testsRun) { test in
                    HStack(spacing: 8) {
                        Image(systemName: test.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(test.passed ? .green : .red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(test.testName)
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                            Text("Duration: \(String(format: "%.2f", test.duration))s")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if !test.output.isEmpty && !test.passed {
                            Text(test.output)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            
            Divider()
            
            // Error State
            if let error = worker.errorState {
                GroupBox(label: Label("Encountered Problem", systemImage: "exclamationmark.triangle.fill")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                        if let details = error.details {
                            Text(details)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }
    
    // MARK: - Timeline Section
    
    @ViewBuilder
    private func timelineSection(_ worker: Worker) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Event Timeline (\(worker.eventHistory.count))")
                .font(.headline)
            
            let sortedEvents = worker.eventHistory.sorted(by: { $0.timestamp > $1.timestamp })
            
            if sortedEvents.isEmpty {
                Text("No events recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(sortedEvents.prefix(30)) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: event.eventType.icon)
                            .font(.caption)
                            .foregroundStyle(eventColor(for: event.eventType))
                            .frame(width: 16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.message)
                                .font(.system(.caption, design: .monospaced))
                            
                            HStack(spacing: 4) {
                                Text(event.timestamp, style: .time)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                
                                if let file = event.filePath {
                                    Text("•")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    Text(file)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
    
    // MARK: - History & Lineage
    
    @ViewBuilder
    private func historySection(_ worker: Worker) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lineage & Reassignment History")
                .font(.headline)
            
            if let handoff = worker.handoffState {
                GroupBox(label: Label("Handoff Record", systemImage: "arrow.triangle.branch")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reason: \(handoff.reason)")
                            .font(.subheadline.bold())
                        Text("Mode: \(handoff.mode.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Divider().padding(.vertical, 2)
                        
                        Text("Completed Work:")
                            .font(.caption.bold())
                        ForEach(handoff.completedWork, id: \.self) { item in
                            Text("• \(item)")
                                .font(.caption)
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        Text("Remaining Scope:")
                            .font(.caption.bold())
                        Text(handoff.remainingScope)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(6)
                }
            } else if let cancellation = worker.cancellationReason {
                GroupBox(label: Label("Cancellation Record", systemImage: "hand.raised.fill")) {
                    Text("Cancelled: \(cancellation)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(6)
                }
            } else {
                Text("No handoff or cancellation on this Worker. Clean execution lineage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func statusBadgeLarge(for status: WorkerStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(for: status).opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(statusColor(for: status))
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
    
    private func reviewColor(for review: WorkerReviewState) -> Color {
        switch review {
        case .notReviewed: return .secondary
        case .reviewing: return .purple
        case .accepted: return .green
        case .rejected: return .red
        case .repairRequired: return .orange
        }
    }
    
    private func fileIcon(for type: WorkerFileChange.ChangeType) -> String {
        switch type {
        case .created: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "trash.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        }
    }
    
    private func fileColor(for type: WorkerFileChange.ChangeType) -> Color {
        switch type {
        case .created: return .green
        case .modified: return .blue
        case .deleted: return .red
        case .renamed: return .orange
        }
    }
    
    private func eventColor(for eventType: WorkerEventType) -> Color {
        switch eventType {
        case .workerCreated, .workerQueued, .workerStarted: return .secondary
        case .workerProgressUpdated, .workerRecapUpdated: return .blue
        case .workerFileChanged: return .indigo
        case .workerTestStarted, .workerTestCompleted: return .teal
        case .workerReviewStarted, .workerReviewCompleted: return .purple
        case .workerCompleted: return .green
        case .workerFailed, .workerBlocked: return .red
        case .workerCancelled, .workerStandby: return .orange
        case .workerHandoffStarted, .workerHandoffCompleted, .workerRecovered: return .yellow
        }
    }
}
