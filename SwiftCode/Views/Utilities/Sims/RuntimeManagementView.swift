import SwiftUI

struct RuntimeManagementView: View {
    @State private var manager = SimulatorManager.shared

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Runtime Environment SDKs", systemImage: "puzzlepiece.fill")
                        .font(.headline)
                        .foregroundColor(.teal)
                    Spacer()
                }

                Divider()

                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Xcode Toolchain Command Path")
                                .font(.subheadline.bold())
                            Text("/Applications/Xcode.app/Contents/Developer")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simctl CLI Version")
                                .font(.subheadline.bold())
                            Text("CoreSimulator-975.2 / simctl-2.0")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simulator Cache Directory Size")
                                .font(.subheadline.bold())
                            Text("3.42 GB (Includes runtime SDKs & images)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Purge Caches") {
                            // Purge action simulator
                            manager.clearConsoleLogs()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}
