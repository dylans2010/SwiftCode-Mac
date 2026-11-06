// PreviewConsoleView.swift
//
// Ported from Legacy `SwiftCode/Views/Utilities/Sims/PreviewConsoleView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: preview-scoped log filtering; search; export
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftCodeUI
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
                    .liquidGlass(style: .hud, cornerRadius: 6)
                    .frame(height: 120)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .simulatorWorkspaceEmbedded()
    }
}
