import SwiftUI

/// Header toolbar button providing a native entry point to the Workers system from Assist.
/// Displays "Workers · N" with active/total count badge and triggers the full dashboard.
@MainActor
public struct WorkersHeaderButton: View {
    private var runtimeState = WorkerRuntimeState.shared
    @State private var showingDashboard = false
    
    public init() {}
    
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
                WorkersMainView()
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
