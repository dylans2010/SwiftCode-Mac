import SwiftUI

/// Compact timeline and status card embedded within the primary Assist chat/agent view.
/// Observes the single authoritative `WorkerRuntimeState.shared`.
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
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    // Header Bar
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.sequence.fill")
                            .foregroundStyle(.blue)
                            .font(.subheadline)
                        
                        Text("Assist Workers")
                            .font(.subheadline.bold())
                        
                        // Active count indicator
                        let activeCount = runtimeState.activeWorkers.count
                        if activeCount > 0 {
                            Text("\(activeCount) active")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        
                        Spacer()
                        
                        Button {
                            isMainDashboardPresented = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Expand")
                                    .font(.caption.bold())
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Open Full Workers Dashboard")
                    }
                    
                    Divider()
                    
                    // Workers Compact Timeline List
                    VStack(spacing: 8) {
                        ForEach(workers) { worker in
                            Button {
                                selectedWorkerForDetails = worker
                            } label: {
                                compactWorkerRow(worker)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(6)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
            .sheet(item: $selectedWorkerForDetails) { worker in
                WorkersInfoView(workerID: worker.id)
            }
            .sheet(isPresented: $isMainDashboardPresented) {
                WorkersMainView()
            }
        }
    }
    
    // MARK: - Compact Row
    
    @ViewBuilder
    private func compactWorkerRow(_ worker: Worker) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Status Icon with appropriate SF Symbol
            statusIcon(for: worker)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worker.name)
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(worker.role)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    statusBadge(for: worker.status)
                }
                
                // Current Action / Phase
                HStack(spacing: 6) {
                    Text(worker.currentAction.isEmpty ? worker.task : worker.currentAction)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Phase indicator
                    Text(worker.currentPhase.rawValue)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(phaseColor(for: worker.currentPhase))
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
        .contentShape(Rectangle())
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func statusIcon(for worker: Worker) -> some View {
        switch worker.status {
        case .created, .queued, .starting:
            Image(systemName: "hourglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .assigned:
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.subheadline)
                .foregroundStyle(.blue)
        case .working:
            ProgressView()
                .scaleEffect(0.6)
                .tint(.blue)
        case .reviewing:
            Image(systemName: "eye.fill")
                .font(.subheadline)
                .foregroundStyle(.purple)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .standby:
            Image(systemName: "pause.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
        case .blocked:
            Image(systemName: "nosign")
                .font(.subheadline)
                .foregroundStyle(.red)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "hand.raised.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .reassigning:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.subheadline)
                .foregroundStyle(.yellow)
        }
    }
    
    private func statusBadge(for status: WorkerStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(statusColor(for: status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(for: status))
    }
    
    private func statusColor(for status: WorkerStatus) -> Color {
        switch status {
        case .created, .queued, .starting, .cancelled:
            return .secondary
        case .assigned, .working:
            return .blue
        case .reviewing:
            return .purple
        case .completed:
            return .green
        case .standby, .reassigning:
            return .orange
        case .blocked, .failed:
            return .red
        }
    }
    
    private func phaseColor(for phase: WorkerPhase) -> Color {
        switch phase {
        case .implementation:
            return .indigo
        case .testing:
            return .teal
        case .verification:
            return .cyan
        case .review:
            return .purple
        }
    }
}
