import SwiftUI

struct CodexPullRequestView: View {
    @StateObject private var workspace = CodexWorkspaceStore.shared
    @State private var commentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pull Request Review", systemImage: "arrow.triangle.pull")
                    .font(.headline)
                Spacer()
                Text(workspace.prStatus.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(workspace.prStatus.tint.opacity(0.15))
                    .foregroundStyle(workspace.prStatus.tint)
                    .clipShape(Capsule())
            }

            if workspace.changedFiles.isEmpty {
                ContentUnavailableView("No Changed Files", systemImage: "doc.on.doc", description: Text("Once Codex generates output, changed files and review actions will appear here."))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Changed Files")
                        .font(.subheadline.weight(.semibold))
                    ForEach(workspace.changedFiles, id: \.self) { file in
                        HStack {
                            Image(systemName: "doc.text")
                            Text(file)
                            Spacer()
                            Button("Open In History") {
                                if let revision = workspace.fileHistory.first(where: { $0.fileName == file }) {
                                    workspace.selectedRevisionID = revision.id
                                    workspace.previousOutput = workspace.renderedOutput
                                    workspace.renderedOutput = revision.content
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                HStack(spacing: 10) {
                    Button("Approve") { workspace.prStatus = .approved }
                        .buttonStyle(.borderedProminent)
                    Button("Request Changes") { workspace.prStatus = .rejected }
                        .buttonStyle(.bordered)
                    Button("Reset") { workspace.prStatus = .pending }
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reviewer Comments")
                        .font(.subheadline.weight(.semibold))
                    HStack(alignment: .top, spacing: 8) {
                        TextField("Leave a comment on the current Codex session…", text: $commentDraft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            workspace.addComment(commentDraft)
                            commentDraft = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if workspace.comments.isEmpty {
                        Text("No Comments Yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workspace.comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(comment.author)
                                        .font(.caption.weight(.semibold))
                                    Text(comment.date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(comment.body)
                                    .font(.caption)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
