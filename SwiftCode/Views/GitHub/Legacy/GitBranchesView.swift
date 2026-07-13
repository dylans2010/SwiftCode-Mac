import SwiftUI

@MainActor
struct GitBranchesView: View {
    let branches: [GitBranch]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Git Branches Directory", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundColor(.blue)
                Spacer()
                Button(action: {}) {
                    Label("New Branch", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 16)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            if branches.isEmpty {
                                ContentUnavailableView(
                                    "No Branches Found",
                                    systemImage: "arrow.triangle.branch",
                                    description: Text("No local branches tracked.")
                                )
                                .frame(height: 150)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(branches) { branch in
                                        HStack {
                                            Image(systemName: "arrow.triangle.branch")
                                                .foregroundStyle(branch.isCurrent ? .green : .secondary)
                                            Text(branch.name)
                                                .fontWeight(branch.isCurrent ? .bold : .regular)
                                            if branch.isCurrent {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                            Spacer()
                                            if branch.isRemote {
                                                Text("remote")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.15))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        .padding(8)
                                        .background(branch.isCurrent ? Color.green.opacity(0.05) : Color.secondary.opacity(0.04))
                                        .cornerRadius(6)
                                        .contextMenu {
                                            Button("Checkout") { /* Checkout */ }
                                            Button("Merge into current") { /* Merge */ }
                                            Divider()
                                            Button("Delete", role: .destructive) { /* Delete */ }
                                        }
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
        .sourceControlEmbedded()
    }
}
