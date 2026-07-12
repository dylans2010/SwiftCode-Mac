import SwiftUI

struct GitNotInstalledView: View {
    var body: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Git Required", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundColor(.red)
                        Spacer()
                    }

                    Text("SwiftCode is unable to find an active Git installation on this system. Git is essential for managing branches, tracking changes, and collaborating on repositories.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Button("Install Git from git-scm.com") {
                        NSWorkspace.shared.open(URL(string: "https://git-scm.com/downloads")!)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}
