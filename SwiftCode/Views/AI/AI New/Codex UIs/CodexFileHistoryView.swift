import SwiftUI

struct CodexFileHistoryView: View {
    @StateObject private var workspace = CodexWorkspaceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("File History", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if workspace.fileHistory.isEmpty {
                ContentUnavailableView("No File Revisions", systemImage: "clock.badge.questionmark", description: Text("Generated file revisions will appear here and sync with the diff viewer."))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(workspace.fileHistory) { revision in
                            Button {
                                workspace.selectedRevisionID = revision.id
                                workspace.previousOutput = workspace.renderedOutput
                                workspace.renderedOutput = revision.content
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(revision.fileName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(revision.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(revision.date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(width: 190, alignment: .leading)
                                .background(workspace.selectedRevisionID == revision.id ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
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
