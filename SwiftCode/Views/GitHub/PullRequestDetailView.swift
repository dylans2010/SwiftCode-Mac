import SwiftUI

@MainActor
struct PullRequestDetailView: View {
    let pr: GitHubPullRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("PR #\(pr.number)", systemImage: "arrow.triangle.pull")
                    .font(.headline)
                    .foregroundStyle(.green)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(pr.title)
                                .font(.title3.bold())

                            HStack(spacing: 8) {
                                Text(pr.state.uppercased())
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())

                                Text("opened by \(pr.user.login) on \(pr.createdAt)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Description Body
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Description", systemImage: "doc.text")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            Text(pr.body ?? "No description provided.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 450)
    }
}
