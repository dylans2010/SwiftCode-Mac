import SwiftUI

@MainActor
struct IssueDetailView: View {
    let issue: GitHubIssue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Issue #\(issue.number)", systemImage: "exclamationmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)

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
                            Text(issue.title)
                                .font(.title3.bold())

                            HStack(spacing: 8) {
                                Text(issue.state.uppercased())
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.12))
                                    .foregroundStyle(.cyan)
                                    .clipShape(Capsule())

                                Text("opened by \(issue.user.login) on \(issue.createdAt)")
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

                            Text(issue.body ?? "No description provided.")
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
