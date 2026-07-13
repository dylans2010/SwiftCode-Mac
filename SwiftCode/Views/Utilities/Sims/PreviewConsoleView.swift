import SwiftUI

@MainActor
struct PreviewConsoleView: View {
    @State private var manager = PreviewManager.shared

    var body: some View {
        VStack(spacing: 0) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Preview Logs & Build Trace", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Clear") {
                            manager.clearLogs()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if manager.buildLogs.isEmpty {
                                Text("No preview logs recorded.")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(manager.buildLogs, id: \.self) { log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(log.contains("failed") || log.contains("Error") ? .red : .primary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .background(Color.black.opacity(0.12))
                    .cornerRadius(6)
                    .frame(height: 120)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .simulatorWorkspaceEmbedded()
    }
}
