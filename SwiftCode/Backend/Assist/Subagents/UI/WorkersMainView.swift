import SwiftUI

/// Complete dashboard view for all Assist Workers associated with the active task.
/// Displays overarching metrics, concurrency states, dependency mapping, and allows drill-down.
/// Observes the single authoritative `WorkerRuntimeState.shared`.
@MainActor
public struct WorkersMainView: View {
    private var runtimeState = WorkerRuntimeState.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var filterMode: FilterMode = .all
    @State private var selectedWorkerForDetails: Worker? = nil
    
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
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Assist Workers Dashboard")
                        .font(.title2.bold())
                    Text("Native Multi-Worker Autonomous Execution System")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Metrics Summary Bar
            metricsSummaryBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            
            Divider()
            
            // Filter Bar
            HStack {
                Picker("Filter", selection: $filterMode) {
                    ForEach(FilterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                
                Spacer()
                
                Text("\(filteredWorkers.count) Workers")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            
            Divider()
            
            // Worker Cards Grid / List
            ScrollView {
                if filteredWorkers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No Workers match the selected filter.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredWorkers) { worker in
                            workerDashboardCard(worker)
                                .onTapGesture {
                                    selectedWorkerForDetails = worker
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 700, idealWidth: 840, minHeight: 520, idealHeight: 640)
        .sheet(item: $selectedWorkerForDetails) { worker in
            WorkersInfoView(workerID: worker.id)
        }
    }
    
    // MARK: - Metrics Summary Bar
    
    @ViewBuilder
    private var metricsSummaryBar: some View {
        HStack(spacing: 12) {
            metricCard(
                title: "Total Workers",
                value: "\(runtimeState.allWorkers.count)",
                icon: "person.3.fill",
                color: .primary
            )
            
            metricCard(
                title: "Active",
                value: "\(runtimeState.activeWorkers.count)",
                icon: "bolt.fill",
                color: .blue
            )
            
            metricCard(
                title: "Completed",
                value: "\(runtimeState.completedWorkers.count)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            metricCard(
                title: "Files Changed",
                value: "\(totalFilesChangedCount)",
                icon: "doc.badge.gearshape.fill",
                color: .indigo
            )
        }
    }
    
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Worker Dashboard Card
    
    @ViewBuilder
    private func workerDashboardCard(_ worker: Worker) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                statusIcon(for: worker.status)
                
                Text(worker.name)
                    .font(.headline)
                
                Text("•")
                    .foregroundStyle(.secondary)
                
                Text(worker.role)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                statusBadge(for: worker.status)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            // Task and Scope
            Text(worker.task)
                .font(.system(.subheadline, design: .default))
                .lineLimit(2)
            
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(worker.scope)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Divider()
            
            // Current Action & Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(worker.currentAction.isEmpty ? "Standing by" : worker.currentAction)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(Int(worker.progressFraction * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                ProgressView(value: worker.progressFraction)
                    .tint(worker.status == .failed ? .red : .blue)
            }
            
            // Bottom stats footer
            HStack(spacing: 16) {
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
                
                Text("Review: \(worker.reviewState.rawValue)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(reviewColor(for: worker.reviewState))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor(for: worker), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }
    
    // MARK: - Helpers & Filtering
    
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
    
    private var totalFilesChangedCount: Int {
        var paths = Set<String>()
        for worker in runtimeState.allWorkers {
            for change in worker.fileChanges {
                paths.insert(change.path)
            }
        }
        return paths.count
    }
    
    private func borderColor(for worker: Worker) -> Color {
        if worker.status == .failed || worker.status == .blocked {
            return Color.red.opacity(0.4)
        } else if worker.status == .working {
            return Color.blue.opacity(0.3)
        } else if worker.status == .completed {
            return Color.green.opacity(0.3)
        }
        return Color.clear
    }
    
    @ViewBuilder
    private func statusIcon(for status: WorkerStatus) -> some View {
        switch status {
        case .created, .queued, .starting:
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
        case .assigned:
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(.blue)
        case .working:
            ProgressView()
                .scaleEffect(0.5)
        case .reviewing:
            Image(systemName: "eye.fill")
                .foregroundStyle(.purple)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .standby:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
        case .blocked:
            Image(systemName: "nosign")
                .foregroundStyle(.red)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.secondary)
        case .reassigning:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.yellow)
        }
    }
    
    private func statusBadge(for status: WorkerStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusColor(for: status).opacity(0.16), in: Capsule())
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
}
