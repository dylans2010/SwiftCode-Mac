import SwiftUI
import SwiftCodeAssistant

/// Header toolbar button providing a native entry point to the Workers
/// system from Assist. Displays "Workers · N" with an active-worker
/// count and a live dot, and opens the full dashboard.
///
/// Port of Legacy
/// `SwiftCode/Backend/Assist/Subagents/UI/WorkersHeaderButton.swift`,
/// rebuilt for the SwiftCodeUI target (default accent, no Legacy orange).
///
/// Wiring: reads the injected `WorkerRuntimeState` (default
/// `.shared`). The dashboard sheet is handed the same instance so the
/// button and the dashboard always agree on live counts.
@MainActor
public struct WorkersHeaderButton: View {
    @Bindable var runtimeState: WorkerRuntimeState
    @State private var showingDashboard = false

    public init(runtimeState: WorkerRuntimeState = .shared) {
        self.runtimeState = runtimeState
    }

    @ViewBuilder
    public var body: some View {
        if !runtimeState.allWorkers.isEmpty {
            Button {
                showingDashboard = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.caption)
                        .foregroundStyle(runtimeState.activeWorkers.isEmpty ? Color.secondary : Color.blue)

                    Text(buttonTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(runtimeState.activeWorkers.isEmpty ? Color.secondary : Color.primary)

                    if !runtimeState.activeWorkers.isEmpty {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Inspect Active Assist Workers")
            .sheet(isPresented: $showingDashboard) {
                WorkersMainView(runtimeState: runtimeState)
            }
        } else {
            Button {
                showingDashboard = true
            } label: {
                Image(systemName: "person.3.sequence")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Workers Dashboard (No Active Workers)")
            .sheet(isPresented: $showingDashboard) {
                WorkersMainView(runtimeState: runtimeState)
            }
        }
    }

    private var buttonTitle: String {
        let activeCount = runtimeState.activeWorkers.count
        if activeCount > 0 {
            return "Workers · \(activeCount)"
        } else if !runtimeState.allWorkers.isEmpty {
            return "Workers · \(runtimeState.allWorkers.count)"
        } else {
            return "Workers"
        }
    }
}
