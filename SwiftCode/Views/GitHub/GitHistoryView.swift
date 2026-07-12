import SwiftUI

struct GitHistoryView: View {
    let commits: [GitCommit]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Commit Logs History", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                }

                if commits.isEmpty {
                    ContentUnavailableView(
                        "No Commits Found",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("There is no commit history on this branch yet.")
                    )
                    .frame(height: 150)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(commits) { commit in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(commit.message)
                                    .font(.headline)
                                    .lineLimit(1)

                                HStack {
                                    Label(commit.author, systemImage: "person.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Text(commit.id.prefix(7))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)

                                    Text(commit.date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}
