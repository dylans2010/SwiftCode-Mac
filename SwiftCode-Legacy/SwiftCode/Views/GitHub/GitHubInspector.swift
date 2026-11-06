import SwiftUI

@MainActor
struct GitHubInspector: View {
    let project: Project?
    var gitViewModel: GitViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Label("Repository Info", systemImage: "info.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)

                Divider()

                // Working directory status
                if let status = gitViewModel.status {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Local Status")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Label(status.branchName, systemImage: "arrow.triangle.branch")
                            .font(.subheadline.bold())

                        HStack(spacing: 12) {
                            Label("\(status.ahead)", systemImage: "arrow.up.circle.fill")
                                .foregroundStyle(.green)
                            Label("\(status.behind)", systemImage: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pending Changes")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        let staged = status.files.filter { $0.isStaged }.count
                        let unstaged = status.files.filter { !$0.isStaged }.count

                        Text("\(staged) Staged Files")
                            .font(.subheadline)
                        Text("\(unstaged) Unstaged Files")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                }

                if let linkedRepo = project?.githubRepo, !linkedRepo.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Linked Remote")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Text(linkedRepo)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(16)
        }
        .frame(minWidth: 200, idealWidth: 240)
        .background(.ultraThinMaterial)
    }
}
