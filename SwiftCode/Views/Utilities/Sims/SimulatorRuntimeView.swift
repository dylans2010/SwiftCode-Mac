import SwiftUI

@MainActor
struct SimulatorRuntimeView: View {
    @State private var manager = SimulatorManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("SDK Runtimes", systemImage: "square.stack.3d.down.right")
                    .font(.headline)
                    .foregroundColor(.cyan)
                Spacer()
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            if manager.runtimes.isEmpty {
                                Text("No available runtimes discovered.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(manager.runtimes) { runtime in
                                        HStack {
                                            Image(systemName: "opticaldisc")
                                                .foregroundColor(.cyan)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(runtime.name)
                                                    .font(.subheadline.bold())
                                                Text(runtime.identifier)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            Text(runtime.isAvailable ? "Installed" : "Unavailable")
                                                .font(.caption.bold())
                                                .foregroundColor(runtime.isAvailable ? .green : .red)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(runtime.isAvailable ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.04))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
        }
        .simulatorWorkspaceEmbedded()
    }
}
