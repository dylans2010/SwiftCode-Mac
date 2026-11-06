import SwiftUI

@MainActor
struct GitNotInstalledView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Git Required", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundColor(.red)
                Spacer()
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("SwiftCode is unable to find an active Git installation on this system. Git is essential for managing branches, tracking changes, and collaborating on repositories.")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            Button("Install Git from git-scm.com") {
                                NSWorkspace.shared.open(URL(string: "https://git-scm.com/downloads")!)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.large)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
        }
        .sourceControlEmbedded()
    }
}
