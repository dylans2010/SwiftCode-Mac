import SwiftUI

struct OperationQueueView: View {
    @State private var queue = OperationQueueManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Operational Task Queue")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Track asynchronous processes, build compiling steps, and diagnostic scan workloads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            if queue.tasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks in Queue", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("As background compiling and workspace audits execute, they will appear here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.tasks) { task in
                    GroupBox {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.name)
                                    .font(.headline)
                                Text("Status: \(task.status)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if task.status == "Executing" {
                                ProgressView(value: task.progress, total: 1.0)
                                    .frame(width: 150)
                            } else {
                                Image(systemName: task.status == "Completed" ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.status == "Completed" ? .green : .secondary)
                            }
                        }
                        .padding(6)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
